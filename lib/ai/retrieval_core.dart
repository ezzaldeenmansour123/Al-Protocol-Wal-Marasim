// Pure Dart فقط — لا يستورد شيئاً غير dart:core، ولا Flutter ولا sqflite
// ولا أي شبكة. هذه الطبقة هي قلب الاسترجاع (R) في RAG: تطبيع عربي،
// استخراج مصطلحات، تعبيرات FTS5، نماذج المقاطع، وقرار الرفض.
// لا توليد نصوص هنا أبداً: كل إجابة لاحقة تُبنى حرفياً من المقاطع
// المسترجعة، وإن لم توجد مقاطع كافية يُعرض نص الرفض الثابت.
//
// التطابق مع lib/db.dart: دوال normalizeAr وqueryTerms وقائمتا
// arStopwords وwordVariants منسوخة حرفياً من db.dart (مع تعليق يوثق
// ذلك عند كل عنصر)، لأن التطبيع يجب أن يبقى متطابقاً بين الاستعلام
// والفهرسة. أي تغيير في التطبيع هنا يجب أن يُطبَّق في db.dart
// وفي tools/build_db.py (دالة norm) في الوقت نفسه.

/// جملة الرفض الواحدة الثابتة في كل المسارات (V2_PLAN §2.5).
/// تُعرض حرفياً عند صفر نتائج أو نتائج ضعيفة — لا صياغة بديلة لها.
const String refusalText =
    'لا تتوفر في قاعدة المعرفة الحالية معلومات موثوقة وكافية للإجابة عن هذا السؤال.';

/// وسم المقاطع المقتبسة حرفياً من قاعدة المعرفة (بلا توليد).
const String retrievalOnlyTag = 'من قاعدة المعرفة — بلا توليد';

/// عتبة الصلة لقرار الرفض (انظر [evaluateRetrieval]):
/// يُقبل المقطع الوحيد فقط إن طابق مصطلحين مميزين على الأقل من السؤال.
/// أقل من ذلك مع نتيجة واحدة = صلة ضعيفة = رفض.
const int minMatchedTermsForAcceptance = 2;

/// عدد المرشحين الذين يُجلبون من كل مرحلة FTS5 قبل إعادة الترتيب
/// (R1): يُجلب 20 مرشحاً ثم يُعاد ترتيبهم بمطابقة العنوان ويُؤخذ
/// الأعلى، لأن رتبة bm25 وحدها تُسقط مواضيع صحيحة خارج أول 10
/// عندما تكون كل مصطلحات السؤال شائعة (رتبة ≈ 0) — مثال C02 حيث
/// كان الموضوع المتوقع P2C1-M2-01 في المرتبة 11 قبل R1.
const int ftsFetchLimit = 20;

/// أقصى طول للمقتطف المعروض من المقطع (أحرف).
const int maxExcerptLength = 600;

// ── التطبيع العربي ──────────────────────────────────────────────
/// منسوخ حرفياً من normalizeAr في lib/db.dart — يجب أن يبقى متطابقاً.
/// R1: الأحرف اللاتينية تُصغَّر (toLowerCase) حتى تعمل كلمات التوقف
/// والمتغيرات الإنجليزية بغض النظر عن كتابة السؤال ('What' == 'what').
/// العربية لا تتأثر؛ وFTS5 يطوي حالة ASCII أصلاً فلا يتغير الفهرس.
String normalizeAr(String s) {
  s = s.toLowerCase();
  s = s
      .replaceAll('\u0648\u0670', 'ا')
      .replaceAll('\u0649\u0670', 'ى')
      .replaceAll('\u0670', 'ا');
  s = s.replaceAll(RegExp(r'[\u064B-\u065F\u06D6-\u06ED\u0640]'), '');
  s = s
      .replaceAll(RegExp(r'[إأآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
  s = s.replaceAll(RegExp(r'[^\u0621-\u064A\u0660-\u0669a-zA-Z0-9\s]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// منسوخ حرفياً من arStopwords في lib/db.dart.
/// كلمات السؤال العربية التي لا تحمل معنى بحثياً. كل المدخلات بصيغة
/// مطبَّعة (انظر normalizeAr: ة→ه، ى→ي، إأآ→ا).
const arStopwords = {
  'كيف',
  'ما',
  'ماذا',
  'هل',
  'لماذا',
  'متي',
  'اين',
  'من',
  'اريد',
  'اعطني',
  'ابحث',
  'ارني',
  'اظهر',
  'اعرض',
  'هات',
  'احضر',
  'اذكر',
  'اورد',
  'هو',
  'هي',
  'في',
  'الي',
  'عن',
  'علي',
  'مع',
  'هذا',
  'هذه',
  'ذلك',
  'تلك',
  'كان',
  'يكون',
  'تتم',
  'يتم',
  'يضم',
  'خمس',
  'اربع',
  'ثلاث',
  'ست',
  'سبع',
  'ثمان',
  'تسع',
  'عشر',
  'واحد',
  'اثنان',
  'اثنين',
  'بين',
  'بعد',
  'قبل',
  'عند',
  'لدي',
  'ان',
  'انه',
  'انها',
  'او',
  'ام',
  'بل',
  'لكن',
  'ثم',
  'كما',
  'اي',
  'كل',
  'بعض',
  'غير',
  'دون',
  'ضد',
  'نحو',
  'حول',
  'داخل',
  'خارج',
  'فوق',
  'تحت',
  'امام',
  'خلف',
  'خلال',
  'اثناء',
  'منذ',
  'حتي',
  'لكي',
  'لان',
  'اذا',
  'عندما',
  'بينما',
  'حيث',
  'الذي',
  'التي',
  'الذين',
  'ارتب',
  'اعد',
  'اكتب',
  'اشرح',
  'عرف',
  'لي',
  'ليس',
  'قد',
  'لقد',
  'سوف',
  'سي',
  'بان',
  'فان',
  'انما',
  'اما',
  'ايضا',
  'فقط',
  'جدا',
  'نفس',
  'ذات',
  'الان',
  'اليوم',
  'غدا',
  'ايه',
  'ايها',
  'ايتها',
  'اولا',
  'ثانيا',
  'ثالثا',
  'مثلا',
  'ممكن',
  'يمكن',
  'ارغب',
  'احتاج',
  'اسال',
};

/// كلمات التوقف الإنجليزية (R1 — نظير arStopwords للأسئلة الإنجليزية):
/// أدوات الاستفهام والربط وأفعال السؤال التي لا تحمل معنى بحثياً.
/// تُحذف من مصطلحات الاستعلام فقط؛ لم تُحذف كلمات ذات معنى مثل
/// state وarticle وprecedence وmission وnational وofficial.
/// القائمة مطابقة لـ EN_STOPWORDS في tools/run_baseline.py.
const enStopwords = {
  'what',
  'which',
  'who',
  'whom',
  'whose',
  'when',
  'where',
  'why',
  'how',
  'is',
  'are',
  'was',
  'were',
  'be',
  'been',
  'being',
  'am',
  'do',
  'does',
  'did',
  'can',
  'could',
  'should',
  'would',
  'may',
  'might',
  'shall',
  'will',
  'the',
  'a',
  'an',
  'and',
  'or',
  'but',
  'if',
  'then',
  'than',
  'so',
  'of',
  'in',
  'on',
  'at',
  'to',
  'for',
  'by',
  'with',
  'from',
  'about',
  'into',
  'over',
  'under',
  'between',
  'through',
  'during',
  'before',
  'after',
  'above',
  'below',
  'up',
  'down',
  'out',
  'off',
  'as',
  'it',
  'its',
  'this',
  'that',
  'these',
  'those',
  'there',
  'here',
  'he',
  'she',
  'they',
  'we',
  'you',
  'i',
  'his',
  'her',
  'their',
  'our',
  'your',
  'my',
  'me',
  'him',
  'us',
  'them',
  'not',
  'no',
  'yes',
  'compare',
  'explain',
  'describe',
  'discuss',
  'outline',
  'list',
  'give',
  'state',
  'name',
  'tell',
  'write',
  'quote',
  'true',
  'false',
  'according',
  'book',
  'say',
  'says',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'twenty',
  'first',
  'second',
  'vs',
  'versus',
};

/// منسوخ حرفياً من _wordVariants في lib/db.dart (أصبح علنياً هنا لأن
/// طبقة الاسترجاع تحتاجه).
/// أزواج مفرد/جمع لا يربطها التطابق البادئ وحده في FTS5
/// (وفد ≠ وفود، رئيس ≠ رؤساء). المفاتيح والقيم بصيغ مطبَّعة.
///
/// إضافات R1 (موثقة في تقرير القياس R1؛ مطابقة في lib/db.dart
/// وفي WORD_VARIANTS في tools/run_baseline.py):
/// - مرادفات موضعية من نص المواضيع نفسها: مطار↔وصول (الاستقبال في
///   المطار)، وفد↔ضيف (الوفد ضيوف رسميون)، استقبال↔ترحيب،
///   مأدبة↔عشاء، جلوس↔مقاعد، اجتماع↔مؤتمر، هدايا↔هدية،
///   نشيد↔أناشيد، هيكل↔إدارة/تنظيم.
/// - اتجاه واحد فقط: ترتيب→أسبقية (السؤال بصيغة «رتّب» يطابق مواضيع
///   الأسبقية؛ العكس لم يُضف حتى لا تُخفَّف أسئلة الأسبقية بمواضيع
///   «ترتيب» العامة).
/// - أفعال→أسماء: يدير→إدارة، ينظم→تنظيم، يستقبل→استقبال،
///   يقدم→تقديم، يودع→توديع، يوقع→توقيع، يرتب→ترتيب.
/// - صيغ التنوين/الظرف: مؤتمراً→مؤتمر، دولياً→دولي/دولية،
///   رسمياً→رسمي/رسمية، سفيراً→سفير، وفداً→وفد، ضيفاً→ضيف،
///   موقفاً→موقف.
/// - جمع إنجليزي لا يربطه البادئ: ceremony/ceremonies،
///   country/countries، embassy/embassies، city/cities،
///   party/parties، body/bodies.
const wordVariants = {
  'وفد': ['وفود', 'ضيف', 'ضيوف'],
  'وفود': ['وفد'],
  'سفير': ['سفراء'],
  'سفراء': ['سفير'],
  'وزير': ['وزراء'],
  'وزراء': ['وزير'],
  'رئيس': ['رؤساء'],
  'رؤساء': ['رئيس'],
  'علم': ['اعلام'],
  'اعلام': ['علم'],
  'لقب': ['القاب'],
  'القاب': ['لقب'],
  'ملك': ['ملوك'],
  'ملوك': ['ملك'],
  'امير': ['امراء'],
  'امراء': ['امير'],
  'ضيف': ['ضيوف', 'وفد', 'وفود'],
  'ضيوف': ['ضيف', 'وفد', 'وفود'],
  'قاعده': ['قواعد'],
  'قواعد': ['قاعده'],
  'وثيقه': ['وثائق'],
  'وثائق': ['وثيقه'],
  'مذكره': ['مذكرات'],
  'مذكرات': ['مذكره'],
  'برنامج': ['برامج'],
  'برامج': ['برنامج'],
  'دوله': ['دول'],
  'دول': ['دوله'],
  'اتفاقيه': ['اتفاقيات'],
  'اتفاقيات': ['اتفاقيه'],
  'دعوه': ['دعوات'],
  'دعوات': ['دعوه'],
  'زياره': ['زيارات'],
  'زيارات': ['زياره'],
  'مناسبه': ['مناسبات'],
  'مناسبات': ['مناسبه'],
  'مطار': ['وصول'],
  'وصول': ['مطار'],
  'استقبال': ['ترحيب'],
  'ترحيب': ['استقبال'],
  'مادبه': ['مادب', 'عشاء'],
  'مادب': ['مادبه', 'عشاء'],
  'عشاء': ['مادبه', 'مادب'],
  'جلوس': ['مقاعد', 'مقعد'],
  'مقاعد': ['جلوس'],
  'مقعد': ['جلوس', 'مقاعد'],
  'اجتماع': ['مؤتمر'],
  'مؤتمر': ['اجتماع'],
  'هدايا': ['هديه'],
  'هديه': ['هدايا'],
  'نشيد': ['اناشيد'],
  'اناشيد': ['نشيد'],
  'هيكل': ['اداره', 'تنظيم'],
  'يدير': ['اداره'],
  'ترتيب': ['اسبقيه'],
  'مؤتمرا': ['مؤتمر'],
  'دوليا': ['دوليه', 'دولي'],
  'رسميا': ['رسميه', 'رسمي'],
  'سفيرا': ['سفير'],
  'وفدا': ['وفد'],
  'ضيفا': ['ضيف'],
  'موقفا': ['موقف'],
  'تكريم': ['تشريفات'],
  'تشريفات': ['تكريم'],
  'ينظم': ['تنظيم'],
  'يستقبل': ['استقبال'],
  'يقدم': ['تقديم'],
  'يودع': ['توديع'],
  'يوقع': ['توقيع'],
  'يرتب': ['ترتيب'],
  'ceremony': ['ceremonies'],
  'ceremonies': ['ceremony'],
  'country': ['countries'],
  'countries': ['country'],
  'embassy': ['embassies'],
  'embassies': ['embassy'],
  'city': ['cities'],
  'cities': ['city'],
  'party': ['parties'],
  'parties': ['party'],
  'body': ['bodies'],
  'bodies': ['body'],
};

/// منسوخ حرفياً من queryTerms في lib/db.dart.
/// مصطلحات بحث ذات معنى: مطبَّعة مع إزالة كلمات التوقف العربية
/// والإنجليزية (R1). يعود إلى كل المصطلحات عندما يكون السؤال كلمات
/// توقف فقط (مثلاً «كيف؟»).
List<String> queryTerms(String q) {
  final all = normalizeAr(q).split(' ').where((t) => t.isNotEmpty).toList();
  final kept = all
      .where((t) => !arStopwords.contains(t) && !enStopwords.contains(t))
      .toList();
  return kept.isEmpty ? all : kept;
}

// ── التجريد الصرفي الآلي للمصطلحات (R1) ──────────────────────────
/// يجرّد بادئة واحدة فقط من المصطلح (مطابق لـ _strip_prefix في
/// tools/build_db.py الذي يستخدمه search_norm وقت الفهرسة: بادئة
/// واحدة لا سلسلة). التجريد المتسلسل ممنوع: كان يأكل الكلمات
/// (كلمة → لمه → مه) ويولّد متغيرات زائفة.
String? _stripOnePrefix(String w) {
  for (final p in ['وال', 'فال', 'بال', 'لل', 'كال']) {
    if (w.startsWith(p) && w.length - p.length >= 2) return w.substring(p.length);
  }
  if (w.startsWith('ال') && w.length - 2 >= 3) return w.substring(2);
  for (final p in ['و', 'ف', 'ب', 'ل', 'ك']) {
    if (w.startsWith(p) && w.length - 1 >= 2) return w.substring(1);
  }
  return null;
}

/// لواحق الضمائر المتصلة (الأطول أولاً) — تُجرَّد عندما يبقى جذر
/// طوله 4 أحرف فأكثر (حتى لا تُجرَّد «دولة» إلى «دول»).
const _pronounSuffixes = [
  'هما',
  'هم',
  'هن',
  'كما',
  'كن',
  'ها',
  'ه',
  'ك',
  'ي',
  'نا',
  'ني',
];

/// الصيغ القاعدية للمصطلح: المصطلح نفسه + صيغة بلا بادئة واحدة +
/// صيغ بلا لاحقة ضمير/مثنى/جمع (ات/ان/ين/ون). صرف آلي فقط، بلا
/// دلالة: كل صيغة بديل OR إضافي للمصطلح نفسه.
Set<String> _baseForms(String t) {
  final forms = <String>{t};
  final stripped = _stripOnePrefix(t);
  if (stripped != null) forms.add(stripped);
  final extra = <String>{};
  for (final f in forms) {
    for (final suf in _pronounSuffixes) {
      if (f.endsWith(suf) && f.length - suf.length >= 4) {
        extra.add(f.substring(0, f.length - suf.length));
      }
    }
    for (final suf in ['ات', 'ان', 'ين', 'ون']) {
      if (f.endsWith(suf) && f.length - suf.length >= 3) {
        extra.add(f.substring(0, f.length - suf.length));
      }
    }
  }
  forms.addAll(extra);
  return forms;
}

/// كل متغيرات مصطلح واحد لمجموعة FTS5 ولعدّ المطابقة:
/// الصيغ القاعدية + مرادفات wordVariants لكل صيغة + صيغة «ال».
/// المصطلح نفسه يُحفَظ دائماً؛ المتغيرات المولَّدة تُسقَط إن كانت
/// كلمة توقف أو أقصر من 3 أحرف («وما» → «ما» كانت تطابق كسلسلة
/// جزئية في كل نص تقريباً قبل R1). مطابقة لـ term_variants في
/// tools/run_baseline.py و_db.dart.
Set<String> termVariants(String t) {
  final vs = <String>{t};
  for (final b in _baseForms(t)) {
    vs.add(b);
    final extra = wordVariants[b];
    if (extra != null) vs.addAll(extra);
    if (b.startsWith('ال') && b.length > 4) {
      vs.add(b.substring(2));
    } else {
      vs.add('ال$b');
    }
  }
  return vs
      .where((v) =>
          v == t || (v.length >= 3 && !arStopwords.contains(v) && !enStopwords.contains(v)))
      .toSet();
}

// ── تعبيرات FTS5 ────────────────────────────────────────────────
/// منسوخ منطقياً من _termGroup في lib/db.dart: كل مصطلح يطابق مع
/// بادئة «ال» أو بدونها، ومرادفات المفرد/الجمع والصيغ الصرفية
/// تُربط بـ OR (انظر [termVariants] — R1).
String ftsTermGroup(String t) {
  final variants = termVariants(t);
  return '(${variants.map((v) => '"$v"*').join(' OR ')})';
}

/// كل المصطلحات بـ AND (المرحلة الصارمة أولاً).
String ftsAndExpression(List<String> terms) =>
    terms.map(ftsTermGroup).join(' AND ');

/// أي مصطلح بـ OR (مرحلة التخفيف الثانية).
String ftsOrExpression(List<String> terms) =>
    terms.map(ftsTermGroup).join(' OR ');

/// أطول مصطلح وحده (مرحلة الملاذ الأخير).
String ftsLongestTermExpression(List<String> terms) {
  final longest = terms.reduce((a, b) => a.length >= b.length ? a : b);
  return ftsTermGroup(longest);
}

/// المراحل الثلاث بالترتيب، مطابقةً لـ _ftsSearch في lib/db.dart:
/// AND ثم OR ثم أطول مصطلح. يُجرَّب كل تعبير حتى يعيد نتائج.
List<String> ftsMatchStages(String query) {
  final terms = queryTerms(query);
  if (terms.isEmpty) return const [];
  if (terms.length == 1) return [ftsTermGroup(terms.first)];
  return [
    ftsAndExpression(terms),
    ftsOrExpression(terms),
    ftsLongestTermExpression(terms),
  ];
}

// ── النماذج ─────────────────────────────────────────────────────
/// مصدر المقطع: 'kb' من مواضيع الكتاب (kb_topics) أو 'article' من
/// مقالات مراسيم الـ49 (احتياطي ثانوي).
enum ChunkOrigin { kb, article }

/// مقطع واحد مسترجع من قاعدة المعرفة — وحدة الاسترجاع والاستشهاد.
/// [rankScore] هو رتبة FTS5 (bm25): قيمة سالبة، والأكثر سلبية تعني
/// صلة أعلى؛ يُستخدم للترتيب فقط ولا يُعرض للمستخدم.
class RetrievedChunk {
  /// معرّف موضوع الكتاب (مثل P2C1-M2-06) أو معرّف المقال نصاً.
  final String topicId;

  /// معرّف المقال الرقمي عندما يكون المصدر مقالاً؛ null لمواضيع الكتاب.
  final int? articleId;

  /// مصدر المقطع: كتاب أم مقال.
  final ChunkOrigin origin;
  final String title;
  final String part;
  final String chapter;
  final String mabhas;

  /// نص المقطع المعروض حرفياً: التعريف أولاً، ثم الشرح، ثم الملخص.
  final String excerpt;

  /// رقم صفحة الكتاب المطبوعة (null للمادة الافتتاحية: بلا ترقيم مطبوع).
  final int? bookPageStart;
  final int? bookPageEnd;

  /// تسمية الصفحة عندما لا يوجد ترقيم مطبوع (مثل المادة الافتتاحية).
  final String? bookPageLabel;

  /// المصدر حرفياً كما في قاعدة المعرفة (اسم الكتاب أو اسم مصدر المقال).
  final String source;

  /// نوع المصدر: 'كتاب' أو 'مرجع خارجي' (من kb_topics.source_type).
  final String sourceType;

  /// حالة النص كما في قاعدة المعرفة ('مصحح آلياً' …) — تُعرض كما هي
  /// ولا تعني مراجعة بشرية.
  final String textStatus;

  /// رتبة FTS5 (سالبة؛ الأكثر سلبية = صلة أعلى).
  final double rankScore;

  /// عدد مصطلحات السؤال المميزة الظاهرة في العنوان/المقتطف
  /// (يُحسب في طبقة الخدمة؛ يُستخدم في قرار الرفض).
  final int matchedTerms;

  /// عدد مصطلحات السؤال المميزة الظاهرة في العنوان وحده
  /// (العنوان + مفردات الفهرس الإنجليزية والعربية — R1).
  /// مفتاح الترتيب الأول في [RetrievalService]: انظر
  /// countTitleMatchedTerms.
  final int titleMatches;

  /// مفردات الفهرس الإنجليزية للموضوع (kb_topics.en_keywords) —
  /// للترتيب فقط، لا تُعرض كمحتوى.
  final String enKeywords;

  /// مفردات الفهرس العربية للموضوع (kb_topics.ar_keywords) —
  /// للترتيب فقط، لا تُعرض كمحتوى.
  final String arKeywords;

  const RetrievedChunk({
    required this.topicId,
    this.articleId,
    this.origin = ChunkOrigin.kb,
    required this.title,
    this.part = '',
    this.chapter = '',
    this.mabhas = '',
    required this.excerpt,
    this.bookPageStart,
    this.bookPageEnd,
    this.bookPageLabel,
    required this.source,
    this.sourceType = 'كتاب',
    this.textStatus = '',
    this.rankScore = 0,
    this.matchedTerms = 0,
    this.titleMatches = 0,
    this.enKeywords = '',
    this.arKeywords = '',
  });

  /// هل لهذا المقطع رقم صفحة كتاب قابل للاستشهاد؟
  bool get hasBookPages => bookPageStart != null && bookPageEnd != null;

  /// «ص. X–Y» أو تسمية الصفحة البديلة أو '' عند غيابها.
  String get bookPagesLabel {
    if (hasBookPages) return 'ص. $bookPageStart–$bookPageEnd';
    if (bookPageLabel != null && bookPageLabel!.isNotEmpty) {
      return bookPageLabel!;
    }
    return '';
  }

  /// سطر الاستشهاد الكامل للعرض:
  /// «المصدر: كتاب البروتوكول والمراسم — ص. X–Y».
  String get citationLine {
    final pages = bookPagesLabel;
    return pages.isEmpty ? 'المصدر: $source' : 'المصدر: $source — $pages';
  }

  RetrievedChunk copyWith({
    int? matchedTerms,
    double? rankScore,
    int? titleMatches,
  }) {
    return RetrievedChunk(
      topicId: topicId,
      articleId: articleId,
      origin: origin,
      title: title,
      part: part,
      chapter: chapter,
      mabhas: mabhas,
      excerpt: excerpt,
      bookPageStart: bookPageStart,
      bookPageEnd: bookPageEnd,
      bookPageLabel: bookPageLabel,
      source: source,
      sourceType: sourceType,
      textStatus: textStatus,
      rankScore: rankScore ?? this.rankScore,
      matchedTerms: matchedTerms ?? this.matchedTerms,
      titleMatches: titleMatches ?? this.titleMatches,
      enKeywords: enKeywords,
      arKeywords: arKeywords,
    );
  }
}

/// نتيجة استرجاع واحدة: المقاطع مرتبة بالصلة، وعلامة الرفض وسببه.
/// [reason] إحدى القيم: null (مقبول)، 'no_results' (صفر نتائج)،
/// 'weak_relevance' (نتائج ضعيفة دون عتبة الصلة).
class RetrievalResult {
  final List<RetrievedChunk> chunks;

  /// true عندما يجب عرض جملة الرفض بدلاً من أي مقطع.
  final bool refused;
  final String? reason;

  /// false عندما غاب جدول kb_topics (قاعدة قديمة v1) فعمل الاسترجاع
  /// على المقالات فقط.
  final bool kbAvailable;

  const RetrievalResult({
    required this.chunks,
    required this.refused,
    this.reason,
    required this.kbAvailable,
  });

  /// أعلى مقطع صلة، أو null عند الرفض.
  RetrievedChunk? get top => refused || chunks.isEmpty ? null : chunks.first;

  /// المقاطع ذات الصلة بعد الأعلى.
  List<RetrievedChunk> get related =>
      refused || chunks.length < 2 ? const [] : chunks.sublist(1);
}

// ── بناء المقتطف وعدّ المصطلحات المطابقة ────────────────────────
/// يبني المقتطف المعروض من حقول الموضوع: التعريف أولاً، ثم الشرح،
/// ثم الملخص؛ يُقصّ إلى [maxExcerptLength] حرفاً مع '…' عند الحاجة.
String buildExcerpt({
  String? definition,
  String? explanation,
  String? summary,
  int maxLength = maxExcerptLength,
}) {
  String? pick(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
  final text = pick(definition) ?? pick(explanation) ?? pick(summary) ?? '';
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength).trim()}…';
}

/// عدد مصطلحات السؤال المميزة الظاهرة في [text] (بعد التطبيع)، مع
/// احتساب مرادفات المفرد/الجمع والصيغ الصرفية ([termVariants]).
/// المصطلحات المكررة في السؤال تُحسب مرة واحدة. قياس تقريبي للصلة
/// يُستخدم في قرار الرفض فقط — لا يغني عن رتبة FTS5.
int countMatchedTerms(String text, List<String> terms) {
  final normed = normalizeAr(text);
  var count = 0;
  for (final t in terms.toSet()) {
    if (termVariants(t).any((v) => normed.contains(v))) count++;
  }
  return count;
}

/// عدد مصطلحات السؤال المميزة الظاهرة في عنوان المقطع (R1 — مفتاح
/// ترجيح العنوان): يُحسب في العنوان العربي + مفردات الفهرس
/// الإنجليزية ([enKeywords]) والعربية ([arKeywords])، بالمصطلحات
/// المميزة نفسها ومتغيراتها ([termVariants]). المصطلح المكرر في
/// السؤال يُحسب مرة واحدة. مطابقة لـ count_in في
/// tools/run_baseline.py.
int countTitleMatchedTerms(
  String title,
  List<String> terms, {
  String enKeywords = '',
  String arKeywords = '',
}) {
  final normed = normalizeAr('$title $enKeywords $arKeywords');
  var count = 0;
  for (final t in terms.toSet()) {
    if (termVariants(t).any((v) => normed.contains(v))) count++;
  }
  return count;
}

// ── قرار الرفض ──────────────────────────────────────────────────
/// يقرر قبول المقاطع المسترجعة أو رفضها وعرض جملة الرفض.
///
/// القاعدة الموثقة (عتبة الصلة):
/// 1. صفر مقاطع → رفض ('no_results').
/// 2. مقطع واحد فقط، والسؤال نفسه يحمل مصطلحين ذوي معنى أو أكثر،
///    والمقطع يطابق أقل من [minMatchedTermsForAcceptance] مصطلحاً
///    (أي مصطلحاً واحداً فقط) → رفض ('weak_relevance'): تغطية
///    جزئية لا تكفي للإجابة عن سؤال مركّب.
/// 3. ما عدا ذلك → قبول: سؤال بمصطلح واحد يكفيه مقطع واحد قوي،
///    وسؤال متعدد المصطلحات مع عدة مقاطع يُعرض أعلاها صلة.
///
/// ملاحظة: هذا القرار استرجاعي بحت — لا يولّد نصاً ولا يخمّن.
/// أي رفض يعني أن المساعد يعرض [refusalText] حرفياً.
RetrievalResult evaluateRetrieval(
  List<RetrievedChunk> chunks, {
  required int queryTermCount,
  required bool kbAvailable,
}) {
  if (chunks.isEmpty) {
    return RetrievalResult(
      chunks: const [],
      refused: true,
      reason: 'no_results',
      kbAvailable: kbAvailable,
    );
  }
  final best = chunks.first;
  if (chunks.length == 1 &&
      queryTermCount >= minMatchedTermsForAcceptance &&
      best.matchedTerms < minMatchedTermsForAcceptance) {
    return RetrievalResult(
      chunks: chunks,
      refused: true,
      reason: 'weak_relevance',
      kbAvailable: kbAvailable,
    );
  }
  return RetrievalResult(
    chunks: chunks,
    refused: false,
    reason: null,
    kbAvailable: kbAvailable,
  );
}
