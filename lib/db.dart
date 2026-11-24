import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Must stay identical to norm() in tools/build_db.py.
/// R1: Latin letters are lower-cased so English stopwords, variants and
/// title matching work regardless of question capitalisation.
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

/// Builds an FTS5 MATCH expression: every query term matches with or without
/// the "ال" prefix. Terms are ANDed; variants of one term are ORed.
/// R1: variants come from [_termVariants] — wordVariants for each
/// morphological base form plus one-prefix stripping and trailing
/// pronoun/dual-plural stripping (identical to termVariants in
/// lib/ai/retrieval_core.dart and run_baseline.py).
String _termGroup(String t) {
  final variants = _termVariants(t);
  return '(${variants.map((v) => '"$v"*').join(' OR ')})';
}

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

Set<String> _termVariants(String t) {
  final vs = <String>{t};
  for (final b in _baseForms(t)) {
    vs.add(b);
    final extra = _wordVariants[b];
    if (extra != null) vs.addAll(extra);
    if (b.startsWith('ال') && b.length > 4) {
      vs.add(b.substring(2));
    } else {
      vs.add('ال$b');
    }
  }
  return vs
      .where((v) =>
          v == t ||
          (v.length >= 3 &&
              !arStopwords.contains(v) &&
              !enStopwords.contains(v)))
      .toSet();
}

String _andExpr(List<String> terms) => terms.map(_termGroup).join(' AND ');

String _orExpr(List<String> terms) => terms.map(_termGroup).join(' OR ');

/// Arabic question/request words that carry no search meaning. All entries
/// are in normalized form (see normalizeAr: ة→ه, ى→ي, إأآ→ا).
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

/// English stopwords (R1 — counterpart of arStopwords for English
/// questions). Identical to enStopwords in lib/ai/retrieval_core.dart
/// and EN_STOPWORDS in tools/run_baseline.py. Meaningful words such as
/// state, article, precedence, mission, national and official are NOT
/// stopwords.
const enStopwords = {
  'what', 'which', 'who', 'whom', 'whose', 'when', 'where', 'why', 'how',
  'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am', 'do', 'does',
  'did', 'can', 'could', 'should', 'would', 'may', 'might', 'shall', 'will',
  'the', 'a', 'an', 'and', 'or', 'but', 'if', 'then', 'than', 'so', 'of',
  'in', 'on', 'at', 'to', 'for', 'by', 'with', 'from', 'about', 'into',
  'over', 'under', 'between', 'through', 'during', 'before', 'after',
  'above', 'below', 'up', 'down', 'out', 'off', 'as', 'it', 'its', 'this',
  'that', 'these', 'those', 'there', 'here', 'he', 'she', 'they', 'we',
  'you', 'i', 'his', 'her', 'their', 'our', 'your', 'my', 'me', 'him',
  'us', 'them', 'not', 'no', 'yes', 'compare', 'explain', 'describe',
  'discuss', 'outline', 'list', 'give', 'state', 'name', 'tell', 'write',
  'quote', 'true', 'false', 'according', 'book', 'say', 'says', 'one',
  'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
  'twenty', 'first', 'second', 'vs', 'versus',
};

/// Singular/plural pairs that are NOT prefix extensions of each other, so
/// FTS prefix matching alone cannot connect them (وفد ≠ وفود, رئيس ≠ رؤساء).
/// Keys and values are normalized forms.
/// R1 additions (identical to wordVariants in lib/ai/retrieval_core.dart
/// and WORD_VARIANTS in tools/run_baseline.py): topical synonyms from
/// the topics' own texts (مطار↔وصول، وفد↔ضيف، استقبال↔ترحيب،
/// مأدبة↔عشاء، جلوس↔مقاعد، اجتماع↔مؤتمر، هدايا↔هدية، نشيد↔أناشيد،
/// هيكل↔إدارة/تنظيم)، one-direction ترتيب→أسبقية، verb→noun pairs
/// (يدير→إدارة …)، tanwin/adverb forms (مؤتمراً→مؤتمر …)، and
/// English plurals (ceremony/ceremonies …).
const _wordVariants = {
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

/// Meaningful query terms: normalized, stopwords removed. Falls back to all
/// terms when the query is only stopwords (e.g. «كيف؟»).
/// R1: Arabic AND English stopwords are removed.
List<String> queryTerms(String q) {
  final all = normalizeAr(q).split(' ').where((t) => t.isNotEmpty).toList();
  final kept = all
      .where((t) => !arStopwords.contains(t) && !enStopwords.contains(t))
      .toList();
  return kept.isEmpty ? all : kept;
}

/// Diplomatic precedence ranks (general order; ambassadors within one rank
/// order by credential date — VCDR 1961 Arts. 13 and 16).
/// (key, Arabic label, rank)
const precedenceRanks = [
  ('head_state', 'رئيس دولة / ملك / أمير حاكم', 1),
  ('head_gov', 'رئيس حكومة', 2),
  ('crown', 'ولي عهد / نائب رئيس الدولة', 3),
  ('foreign_minister', 'وزير الخارجية', 4),
  ('ambassador', 'سفير', 5),
  ('minister', 'وزير', 6),
  ('charge', 'قائم بالأعمال', 7),
  ('deputy_minister', 'وكيل وزارة / نائب وزير', 8),
  ('director_general', 'مدير عام', 9),
  ('senior_official', 'مسؤول رفيع', 10),
];

int rankOf(String key) {
  for (final r in precedenceRanks) {
    if (r.$1 == key) return r.$3;
  }
  return 99;
}

/// مصدر كل فئة أسبقية في قاعدة المعرفة، متحقق منه صفحة صفحة
/// ضد kb_topics (2026-11-25). غياب الفئة من الخريطة = بلا مصدر
/// موثق في القاعدة الحالية (تُوسم كذلك في الواجهة ولا تُخترع).
/// - head_state: مبحث «أسبقية الملوك ورؤساء الدول» ص. 65–68.
/// - head_gov وcrown: مبحث «تعارض معايير الأسبقية» ص. 89–91
///   (رئيس الدولة يتقدم على رئيس الحكومة؛ والتفريق بين ولي
///   عهد ومبعوث خاص يسبق كل اعتبار آخر).
/// - ambassador: مبحث «الأسبقية في البعثات الدبلوماسية والقنصلية»
///   ص. 69–71 + فيينا 1961 المادتان 13 و16.
/// - charge: فيينا 1961 المادة 14 (فئات رؤساء البعثات — مقال 8،
///   مصدر متحقق).
/// - foreign_minister وminister وdeputy_minister وdirector_general
///   وsenior_official: لا قاعدة موثقة لها في مواضيع الكتاب.
const precedenceSources = {
  'head_state':
      'كتاب «البروتوكول والمراسم» — مبحث «أسبقية الملوك ورؤساء الدول»، ص. 65–68',
  'head_gov':
      'كتاب «البروتوكول والمراسم» — مبحث «تعارض معايير الأسبقية»، ص. 89–91',
  'crown':
      'كتاب «البروتوكول والمراسم» — مبحث «تعارض معايير الأسبقية»، ص. 89–91',
  'ambassador':
      'كتاب «البروتوكول والمراسم» — مبحث «الأسبقية في مجال البعثات الدبلوماسية والقنصلية»، ص. 69–71؛ اتفاقية فيينا 1961، المادتان 13 و16',
  'charge':
      'اتفاقية فيينا للعلاقات الدبلوماسية 1961، المادة 14 (فئات رؤساء البعثات)',
};

/// مصدر فئة الأسبقية، أو null إن كانت بلا مصدر موثق.
String? precedenceSourceFor(String key) => precedenceSources[key];

String rankLabel(String key) {
  for (final r in precedenceRanks) {
    if (r.$1 == key) return r.$2;
  }
  return key;
}

/// Orders a list of guest maps (with keys rank_category, credential_date,
/// name) by the precedence rules and returns them sorted.
List<Map<String, dynamic>> orderByPrecedence(
    List<Map<String, dynamic>> guests) {
  final list = List<Map<String, dynamic>>.from(guests);
  list.sort((a, b) {
    final ra = rankOf((a['rank_category'] ?? '') as String);
    final rb = rankOf((b['rank_category'] ?? '') as String);
    if (ra != rb) return ra.compareTo(rb);
    final da = ((a['credential_date'] ?? '') as String);
    final db = ((b['credential_date'] ?? '') as String);
    if (da.isNotEmpty && db.isNotEmpty && da != db) return da.compareTo(db);
    if (da.isEmpty && db.isNotEmpty) return 1;
    if (da.isNotEmpty && db.isEmpty) return -1;
    return ((a['name'] ?? '') as String).compareTo((b['name'] ?? '') as String);
  });
  return list;
}

class Article {
  final int id;
  final String title,
      section,
      body,
      ruleType,
      sourceName,
      sourceOrg,
      sourceUrl,
      reviewed;
  const Article(this.id, this.title, this.section, this.body, this.ruleType,
      this.sourceName, this.sourceOrg, this.sourceUrl, this.reviewed);
  factory Article.fromMap(Map<String, Object?> m) => Article(
        m['id'] as int,
        m['title'] as String,
        m['section'] as String,
        m['body'] as String,
        m['rule_type'] as String,
        m['source_name'] as String,
        m['source_org'] as String,
        (m['source_url'] ?? '') as String,
        (m['reviewed'] ?? '') as String,
      );
}

/// موضوع واحد من كتاب «البروتوكول والمراسم» (جدول kb_topics،
/// KNOWLEDGE_BASE_REPORT.md §5). الحقول المنظمة (تعريف/شرح/قواعد/
/// إجراءات/أمثلة/أخطاء/نقاط) تُخزن نصاً أو JSON كما في القاعدة؛
/// وأي حقل null يعني أن العنصر لم يرد في نص المبحث، لا أنه غير
/// موجود أصلاً. حالة textStatus ('مصحح آلياً' …) تُعرض كما هي ولا
/// تعني مراجعة بشرية.
class KbTopic {
  final String id, part, chapter, mabhas, title;
  final String? subsectionsJson, summary, definition, explanation;
  final String? rulesJson,
      proceduresJson,
      examplesJson,
      mistakesJson,
      keyPointsJson;
  final int? bookPageStart, bookPageEnd;
  final String? bookPageLabel;
  final int pdfPageStart, pdfPageEnd;
  final String sourceFile, source, sourceType, textStatus, matchType;
  final int correctionsApplied, residualGarbleCount;
  final String? contentLimitation, matchNote;
  final int? charCount, wordCount;

  /// مفردات الفهرس (R1 — للترتيب فقط، لا تُعرض كمحتوى):
  /// enKeywords ترجمات العناوين ومفردات إنجليزية، وarKeywords
  /// مفردات عربية من نص الموضوع نفسه غائبة عن عنوانه.
  final String? enKeywords, arKeywords;

  const KbTopic(
      this.id,
      this.part,
      this.chapter,
      this.mabhas,
      this.title,
      this.subsectionsJson,
      this.summary,
      this.definition,
      this.explanation,
      this.rulesJson,
      this.proceduresJson,
      this.examplesJson,
      this.mistakesJson,
      this.keyPointsJson,
      this.bookPageStart,
      this.bookPageEnd,
      this.bookPageLabel,
      this.pdfPageStart,
      this.pdfPageEnd,
      this.sourceFile,
      this.source,
      this.sourceType,
      this.textStatus,
      this.matchType,
      this.correctionsApplied,
      this.residualGarbleCount,
      this.contentLimitation,
      this.matchNote,
      this.charCount,
      this.wordCount,
      [this.enKeywords,
      this.arKeywords]);

  factory KbTopic.fromMap(Map<String, Object?> m) => KbTopic(
        m['id'] as String,
        (m['part'] ?? '') as String,
        (m['chapter'] ?? '') as String,
        (m['mabhas'] ?? '') as String,
        (m['title'] ?? '') as String,
        m['subsections'] as String?,
        m['summary'] as String?,
        m['definition'] as String?,
        m['explanation'] as String?,
        m['rules_json'] as String?,
        m['procedures_json'] as String?,
        m['examples_json'] as String?,
        m['mistakes_json'] as String?,
        m['key_points_json'] as String?,
        m['book_page_start'] as int?,
        m['book_page_end'] as int?,
        m['book_page_label'] as String?,
        (m['pdf_page_start'] as int?) ?? 0,
        (m['pdf_page_end'] as int?) ?? 0,
        (m['source_file'] ?? '') as String,
        (m['source'] ?? '') as String,
        (m['source_type'] ?? 'كتاب') as String,
        (m['text_status'] ?? '') as String,
        (m['match_type'] ?? '') as String,
        (m['corrections_applied'] as int?) ?? 0,
        (m['residual_garble_count'] as int?) ?? 0,
        m['content_limitation'] as String?,
        m['match_note'] as String?,
        m['char_count'] as int?,
        m['word_count'] as int?,
        m['en_keywords'] as String?,
        m['ar_keywords'] as String?,
      );

  /// المقتطف المعروض: التعريف أولاً، ثم الشرح، ثم الملخص.
  String get excerpt {
    String? pick(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final text = pick(definition) ?? pick(explanation) ?? pick(summary) ?? '';
    if (text.length <= 600) return text;
    return '${text.substring(0, 600).trim()}…';
  }

  /// «ص. X–Y» أو تسمية الصفحة البديلة أو '' عند غيابها.
  String get bookPagesLabel {
    if (bookPageStart != null && bookPageEnd != null) {
      return 'ص. $bookPageStart–$bookPageEnd';
    }
    if (bookPageLabel != null && bookPageLabel!.isNotEmpty) {
      return bookPageLabel!;
    }
    return '';
  }
}

class Country {
  final int id;
  final String nameAr, nameEn, capital, languages, currency, timezones, system;
  final String? nationalDay;
  final String nationalDayName, protocolNote, titlesNote, flag;
  final String sourceName, sourceOrg, sourceUrl, reviewed;
  const Country(
      this.id,
      this.nameAr,
      this.nameEn,
      this.capital,
      this.languages,
      this.currency,
      this.timezones,
      this.system,
      this.nationalDay,
      this.nationalDayName,
      this.protocolNote,
      this.titlesNote,
      this.flag,
      this.sourceName,
      this.sourceOrg,
      this.sourceUrl,
      this.reviewed);
  factory Country.fromMap(Map<String, Object?> m) => Country(
        m['id'] as int,
        m['name_ar'] as String,
        m['name_en'] as String,
        m['capital'] as String,
        m['languages'] as String,
        m['currency'] as String,
        m['timezones'] as String,
        m['system'] as String,
        m['national_day'] as String?,
        m['national_day_name'] as String,
        m['protocol_note'] as String,
        m['titles_note'] as String,
        m['flag'] as String,
        m['source_name'] as String,
        m['source_org'] as String,
        (m['source_url'] ?? '') as String,
        (m['reviewed'] ?? '') as String,
      );
}

class TemplateDoc {
  final int id;
  final String key,
      titleAr,
      titleEn,
      category,
      bodyAr,
      bodyEn,
      sourceName,
      reviewed;
  const TemplateDoc(this.id, this.key, this.titleAr, this.titleEn,
      this.category, this.bodyAr, this.bodyEn, this.sourceName, this.reviewed);
  factory TemplateDoc.fromMap(Map<String, Object?> m) => TemplateDoc(
        m['id'] as int,
        m['key'] as String,
        m['title_ar'] as String,
        m['title_en'] as String,
        m['category'] as String,
        m['body_ar'] as String,
        m['body_en'] as String,
        m['source_name'] as String,
        (m['reviewed'] ?? '') as String,
      );
}

class NationalDayItem {
  final int countryId;
  final String mmdd, name, countryAr, flag;
  final DateTime nextDate;
  const NationalDayItem(this.countryId, this.mmdd, this.name, this.countryAr,
      this.flag, this.nextDate);
}

class EventItem {
  final int id, guestsExpected;
  final String title, type, date, place, notes, createdAt;
  const EventItem(this.id, this.title, this.type, this.date, this.place,
      this.guestsExpected, this.notes, this.createdAt);
  factory EventItem.fromMap(Map<String, Object?> m) => EventItem(
        m['id'] as int,
        m['title'] as String,
        m['type'] as String,
        m['date'] as String,
        m['place'] as String,
        (m['guests_expected'] as int?) ?? 0,
        (m['notes'] ?? '') as String,
        (m['created_at'] ?? '') as String,
      );
}

class SeatingPlan {
  final int id, seats;
  final String name, shape, createdAt, updatedAt;
  const SeatingPlan(this.id, this.name, this.shape, this.seats, this.createdAt,
      this.updatedAt);
  factory SeatingPlan.fromMap(Map<String, Object?> m) => SeatingPlan(
        m['id'] as int,
        m['name'] as String,
        m['shape'] as String,
        m['seats'] as int,
        (m['created_at'] ?? '') as String,
        (m['updated_at'] ?? '') as String,
      );
}

/// Public reference documents (links only — no copyrighted books).
class LibraryDoc {
  final String title, org, url, kind;
  const LibraryDoc(this.title, this.org, this.url, this.kind);
}

const libraryDocs = [
  LibraryDoc(
      'اتفاقية فيينا للعلاقات الدبلوماسية 1961 (النص الكامل)',
      'الأمم المتحدة — مجموعة المعاهدات',
      'https://treaties.un.org/doc/Treaties/1964/06/19640624%2002-10%20AM/Ch_III_3p.pdf',
      'اتفاقية دولية'),
  LibraryDoc(
      'اتفاقية فيينا للعلاقات القنصلية 1963 (النص الكامل)',
      'الأمم المتحدة — مجموعة المعاهدات',
      'https://treaties.un.org/doc/treaties/1967/06/19670608%2010-36%20am/ch_iii_6p.pdf',
      'اتفاقية دولية'),
  LibraryDoc(
      'ميثاق الأمم المتحدة (النص الكامل)',
      'الأمم المتحدة',
      'https://treaties.un.org/doc/Publication/CTC/uncharter.pdf',
      'وثيقة دولية'),
  LibraryDoc(
      'دليل المراسم — بروتوكول الأمم المتحدة (Manual of Protocol)',
      'الأمم المتحدة — إدارة شؤون الجمعية العامة والمؤتمرات',
      'https://www.un.org/dgacm/en/content/protocol/manual-of-protocol',
      'دليل مراسم'),
  LibraryDoc(
      'صفحة البروتوكول — الأمم المتحدة',
      'الأمم المتحدة — إدارة شؤون الجمعية العامة والمؤتمرات',
      'https://www.un.org/dgacm/en/content/protocol',
      'مرجع رسمي'),
  LibraryDoc(
      'Protocol for the Modern Diplomat',
      'وزارة الخارجية الأمريكية — معهد الخدمة الخارجية (2005)',
      'https://www.govinfo.gov/app/details/GOVPUB-S-PURL-LPS81568',
      'دليل مراسم'),
];

class Repo {
  static final Repo i = Repo._();
  Repo._();
  Database? _db;

  /// قاعدة البيانات المحلية، الإصدار 3 (v2 + جداول الأدوات الجديدة:
  /// وفود وزيارات ومؤتمرات ومآدب ومحادثات محفوظة — كلها بيانات
  /// مستخدم محلية فقط، لا تُمس أبداً عند تحديث جداول المحتوى).
  ///
  /// v1 لم يضبط user_version أبداً (بُنيت القاعدة ببايثون)، لذا تصل
  /// قواعد v1 المثبتة إلى onCreate لا إلى onUpgrade (user_version=0).
  /// onCreate يكتفي بضمان مخطط v2، ويستورد الترحيلُ محتوى الأصول
  /// الجديد عبر فحص البصمة أدناه — فلا تُفقد بيانات المستخدم أبداً.
  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'marasim.db');
    if (!await File(path).exists()) {
      final data = await rootBundle.load('assets/marasim.db');
      await File(path).writeAsBytes(data.buffer.asUint8List());
    }
    final d = await openDatabase(path,
        version: 3, onCreate: _onCreate, onUpgrade: _onUpgrade);
    _db = d;
    // v1.0.1 migration: seating_assignments gains rank_category so a saved
    // seating guest's rank survives reload (v1.0.0 installs lack the column).
    try {
      await _db!.execute(
          'ALTER TABLE seating_assignments ADD COLUMN rank_category TEXT');
    } catch (_) {
      // Column already exists on fresh v1.0.1 installs.
    }
    // جداول الأدوات الجديدة (وفود/زيارات/مؤتمرات/مآدب/محادثات):
    // CREATE TABLE IF NOT EXISTS آمن لإعادة الاستدعاء، فيضمن وجودها
    // مهما كان مسار فتح القاعدة (onCreate أو onUpgrade أو قاعدة قديمة).
    try {
      await _ensureUserToolTables(_db!);
    } catch (_) {
      // Best-effort; the upgrade path below also creates them.
    }
    // مقارنة بصمة الأصول: عند اختلاف assets/marasim.db.sha256 عن
    // البصمة المخزنة في meta تُعاد جداول المحتوى فقط من الأصول.
    // الفشل هنا لا يكسر فتح القاعدة أبداً (تطوير بلا ملف أصول مثلاً).
    try {
      await _refreshContentIfAssetChanged();
    } catch (_) {
      // Content refresh is best-effort; the app works on local content.
    }
    return _db!;
  }

  // ── ترحيل v2 (db_version 1 → 2) ──
  //
  // onCreate: يُستدعى عند أول إنشاء وعند فتح قاعدة قديمة بـ
  // user_version=0 (كل قواعد v1). ينشئ مخطط v2 كاملاً إن غاب؛ وإن
  // كانت نسخة الأصول نفسها v2 فالجداول موجودة أصلاً ولا تُعاد بناؤها
  // (CREATE TABLE IF NOT EXISTS). محتوى الكتاب الجديد يصل عبر
  // فحص البصمة بعد الفتح.
  Future<void> _onCreate(Database db, int version) async {
    await _ensureV2Schema(db);
    await _ensureUserToolTables(db);
    await _setMeta(db, 'db_version', '3');
  }

  // onUpgrade: ترحيل 1→2 داخل transaction واحدة (sqflite ينفذ
  // onUpgrade داخل transaction أصلاً). ينشئ مخطط v2 ويستورد جداول
  // المحتوى من نسخة أصول جديدة؛ جداول بيانات المستخدم لا تُمس.
  // ترحيل 2→3: إنشاء جداول الأدوات الجديدة فقط (وفود/زيارات/
  // مؤتمرات/مآدب/محادثات) — لا مساس بأي بيانات قائمة.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateV1ToV2(db);
    }
    if (oldVersion < 3) {
      await _ensureUserToolTables(db);
      await _setMeta(db, 'db_version', '3');
    }
  }

  Future<void> _migrateV1ToV2(DatabaseExecutor db) async {
    await _ensureV2Schema(db);
    final tmpPath = await _copyAssetToTemp();
    if (tmpPath != null) {
      try {
        await _importContentFromTempDb(db, tmpPath);
      } finally {
        try {
          await File(tmpPath).delete();
        } catch (_) {}
      }
    }
    await _setMeta(db, 'db_version', '2');
  }

  /// ينشئ مخطط v2 كاملاً إن غاب (آمن لإعادة الاستدعاء):
  /// جداول قاعدة المعرفة (KNOWLEDGE_BASE_REPORT.md §5) + جدول
  /// sources العام (V2_PLAN §3.1) + أعمدة articles الجديدة.
  Future<void> _ensureV2Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kb_topics (
        id            TEXT PRIMARY KEY,
        part          TEXT NOT NULL,
        chapter       TEXT NOT NULL,
        mabhas        TEXT NOT NULL,
        title         TEXT NOT NULL,
        subsections   TEXT,
        summary       TEXT,
        definition    TEXT,
        explanation   TEXT,
        rules_json    TEXT,
        procedures_json TEXT,
        examples_json TEXT,
        mistakes_json TEXT,
        key_points_json TEXT,
        book_page_start INTEGER,
        book_page_end   INTEGER,
        book_page_label TEXT,
        pdf_page_start  INTEGER NOT NULL,
        pdf_page_end    INTEGER NOT NULL,
        source_file   TEXT NOT NULL,
        source        TEXT NOT NULL,
        source_type   TEXT NOT NULL DEFAULT 'كتاب',
        text_status   TEXT NOT NULL,
        corrections_applied INTEGER NOT NULL DEFAULT 0,
        residual_garble_count INTEGER NOT NULL DEFAULT 0,
        content_limitation TEXT,
        match_type    TEXT NOT NULL,
        match_note    TEXT,
        char_count    INTEGER,
        word_count    INTEGER,
        en_keywords   TEXT,
        ar_keywords   TEXT
      )''');
    // R1: عمودا مفردات الفهرس في قواعد v2 المثبتة أصلاً (التي أُنشئ
    // جدولها قبل R1): يُضافان إن غابا. جدول FTS بلا تغيير عمداً
    // (انظر tools/build_db.py) فيبقى تحديث المحتوى بالبصمة يعمل.
    for (final entry in {
      'en_keywords': 'TEXT',
      'ar_keywords': 'TEXT',
    }.entries) {
      final kbCols = await _columnsOf(db, 'main', 'kb_topics');
      if (!kbCols.contains(entry.key)) {
        try {
          await db.execute(
              'ALTER TABLE kb_topics ADD COLUMN ${entry.key} ${entry.value}');
        } catch (_) {
          // Column added concurrently: ignore.
        }
      }
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kb_topic_articles (
        topic_id     TEXT NOT NULL REFERENCES kb_topics(id),
        article_no   INTEGER NOT NULL,
        relation     TEXT NOT NULL,
        PRIMARY KEY (topic_id, article_no)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kb_sources (
        id          TEXT PRIMARY KEY,
        title_ar    TEXT NOT NULL,
        title_en    TEXT,
        publisher   TEXT,
        url         TEXT,
        verified    TEXT NOT NULL,
        kind        TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kb_corrections (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        rule        TEXT NOT NULL,
        applications INTEGER NOT NULL,
        example_replacement TEXT
      )''');
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS kb_topics_fts USING fts5(
        title, summary, definition, explanation,
        content='kb_topics', content_rowid='rowid', tokenize='unicode61')''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sources (
        id INTEGER PRIMARY KEY,
        code TEXT UNIQUE NOT NULL,
        name_ar TEXT, name_en TEXT,
        publisher TEXT, url TEXT,
        classification TEXT NOT NULL,
        scope TEXT,
        verified INTEGER NOT NULL DEFAULT 0,
        review_date TEXT
      )''');
    // أعمدة articles الجديدة (V2_PLAN §3.1): تُضاف إن غابت فقط.
    const articleColumns = {
      'source_code': 'TEXT',
      'axis': 'INTEGER',
      'section_code': 'TEXT',
      'source_status': 'TEXT',
    };
    final existing = await _columnsOf(db, 'main', 'articles');
    for (final entry in articleColumns.entries) {
      if (!existing.contains(entry.key)) {
        try {
          await db.execute(
              'ALTER TABLE articles ADD COLUMN ${entry.key} ${entry.value}');
        } catch (_) {
          // Column added concurrently or table missing: ignore.
        }
      }
    }
  }

  /// جداول بيانات المستخدم للأدوات الجديدة (V2_PLAN §1.2: وفود
  /// وزيارات ومؤتمرات ومآدب) + المحادثات المحفوظة (CHARTER_V2 §4.6).
  /// كلها محلية على الجهاز فقط؛ لا تُدرج أبداً في _contentTables
  /// فلا تُمس عند تحديث محتوى الأصول. CREATE TABLE IF NOT EXISTS
  /// فيجوز استدعاؤها من onCreate وonUpgrade وgetter القاعدة.
  Future<void> _ensureUserToolTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delegations (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        country       TEXT NOT NULL DEFAULT '',
        head_name     TEXT NOT NULL DEFAULT '',
        head_title    TEXT NOT NULL DEFAULT '',
        notes         TEXT NOT NULL DEFAULT '',
        visit_id      INTEGER,
        conference_id INTEGER,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delegation_members (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        delegation_id INTEGER NOT NULL,
        name          TEXT NOT NULL,
        title         TEXT NOT NULL DEFAULT '',
        country       TEXT NOT NULL DEFAULT '',
        phone         TEXT NOT NULL DEFAULT '',
        email         TEXT NOT NULL DEFAULT '',
        notes         TEXT NOT NULL DEFAULT '',
        sort_order    INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        title           TEXT NOT NULL,
        sending_country TEXT NOT NULL DEFAULT '',
        host_country    TEXT NOT NULL DEFAULT '',
        head_name       TEXT NOT NULL DEFAULT '',
        arrival_date    TEXT NOT NULL DEFAULT '',
        arrival_time    TEXT NOT NULL DEFAULT '',
        arrival_place   TEXT NOT NULL DEFAULT '',
        departure_date  TEXT NOT NULL DEFAULT '',
        departure_time  TEXT NOT NULL DEFAULT '',
        departure_place TEXT NOT NULL DEFAULT '',
        delegation_id   INTEGER,
        notes           TEXT NOT NULL DEFAULT '',
        created_at      TEXT NOT NULL,
        updated_at      TEXT NOT NULL
      )''');
    // kind: reception | farewell | meeting | field_visit | transport | other
    // الاستقبال والتوديع مرحلتان منفصلتان كما في الكتاب (الباب الثاني،
    // الفصل الأول: مراسم استقبال كبار الشخصيات / مراسم توديعهم).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visit_items (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id   INTEGER NOT NULL,
        kind       TEXT NOT NULL DEFAULT 'other',
        title      TEXT NOT NULL,
        date       TEXT NOT NULL DEFAULT '',
        time       TEXT NOT NULL DEFAULT '',
        place      TEXT NOT NULL DEFAULT '',
        notes      TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conferences (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT NOT NULL,
        place      TEXT NOT NULL DEFAULT '',
        start_date TEXT NOT NULL DEFAULT '',
        end_date   TEXT NOT NULL DEFAULT '',
        notes      TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    // kind: opening | working | closing | other
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conference_sessions (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        conference_id INTEGER NOT NULL,
        kind          TEXT NOT NULL DEFAULT 'working',
        title         TEXT NOT NULL,
        date          TEXT NOT NULL DEFAULT '',
        time          TEXT NOT NULL DEFAULT '',
        place         TEXT NOT NULL DEFAULT '',
        notes         TEXT NOT NULL DEFAULT '',
        sort_order    INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conference_delegations (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        conference_id INTEGER NOT NULL,
        delegation_id INTEGER NOT NULL,
        UNIQUE (conference_id, delegation_id)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS banquets (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT NOT NULL,
        date       TEXT NOT NULL DEFAULT '',
        time       TEXT NOT NULL DEFAULT '',
        place      TEXT NOT NULL DEFAULT '',
        host_name  TEXT NOT NULL DEFAULT '',
        notes      TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    // seat: رقم مقعد طاولة الشرف (0 = بلا مقعد محدد)؛ invited: 1/0.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS banquet_guests (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        banquet_id    INTEGER NOT NULL,
        name          TEXT NOT NULL,
        title         TEXT NOT NULL DEFAULT '',
        country       TEXT NOT NULL DEFAULT '',
        rank_category TEXT NOT NULL DEFAULT '',
        seat          INTEGER NOT NULL DEFAULT 0,
        invited       INTEGER NOT NULL DEFAULT 1,
        sort_order    INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS banquet_items (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        banquet_id INTEGER NOT NULL,
        title      TEXT NOT NULL,
        time       TEXT NOT NULL DEFAULT '',
        notes      TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    // المحادثات المحفوظة: عنوان تلقائي من أول سؤال، والرسائل مع
    // الاستشهادات نصاً. محلية فقط — لا تُرسل أي بيانات خارج الجهاز.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_conversations (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    // role: user | assistant ؛ citations: سطور الاستشهاد مدموجة بنص
    // (موضوع + صفحة كتاب) أو '' عند غيابها.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        role            TEXT NOT NULL,
        text            TEXT NOT NULL,
        citations       TEXT NOT NULL DEFAULT '',
        created_at      TEXT NOT NULL
      )''');
  }

  /// جداول المحتوى فقط — تُستبدل من الأصول عند الترحيل/التحديث.
  /// جداول بيانات المستخدم لا تظهر هنا أبداً ولا تُمس:
  /// favorites, events, event_guests, event_program, checklist_items,
  /// seating_plans, seating_assignments, settings.
  static const _contentTables = [
    'articles',
    'countries',
    'templates',
    'national_days',
    'kb_topics',
    'kb_topic_articles',
    'kb_sources',
    'kb_corrections',
    'sources',
  ];

  static const _contentFtsTables = [
    'articles_fts',
    'countries_fts',
    'templates_fts',
    'kb_topics_fts',
  ];

  /// يقارن بصمة الأصول (assets/marasim.db.sha256) بالبصمة المخزنة في
  /// meta ('asset_sha256')؛ عند الاختلاف (أو غياب المخزنة) يعيد
  /// استيراد جداول المحتوى فقط من نسخة أصول جديدة، داخل transaction
  /// واحدة، دون مساس ببيانات المستخدم. يعيد false بهدوء عندما تكون
  /// الأصول غير متاحة (تطوير بلا ملف أصول مبني).
  Future<bool> _refreshContentIfAssetChanged() async {
    String assetSha;
    try {
      assetSha =
          (await rootBundle.loadString('assets/marasim.db.sha256')).trim();
    } catch (_) {
      return false;
    }
    if (assetSha.isEmpty) return false;
    final stored = await meta('asset_sha256');
    if (stored == assetSha) return false;
    final tmpPath = await _copyAssetToTemp();
    if (tmpPath == null) return false;
    try {
      await _db!.transaction((txn) async {
        await _importContentFromTempDb(txn, tmpPath);
      });
      await _setMeta(_db!, 'asset_sha256', assetSha);
      await _setMeta(_db!, 'db_version', '3');
      return true;
    } finally {
      try {
        await File(tmpPath).delete();
      } catch (_) {}
    }
  }

  /// ينسخ أصول assets/marasim.db إلى ملف مؤقت؛ null عند غياب الأصول.
  Future<String?> _copyAssetToTemp() async {
    try {
      final data = await rootBundle.load('assets/marasim.db');
      final tmp = await getTemporaryDirectory();
      final tmpPath = p.join(tmp.path,
          'marasim-asset-${DateTime.now().microsecondsSinceEpoch}.db');
      await File(tmpPath).writeAsBytes(data.buffer.asUint8List());
      return tmpPath;
    } catch (_) {
      return null;
    }
  }

  /// يستورد جداول المحتوى من نسخة أصول مؤقتة عبر اتصال قراءة ثانٍ.
  /// يعمل داخل transaction المتصل (ترحيل onUpgrade أو تحديث البصمة)
  /// دون ATTACH/DETACH — فـ DETACH يفشل داخل transaction نشطة
  /// (SQLite: database is locked)، كما أثبتت محاكاة الترحيل محلياً.
  /// على المتصل تملك الـ transaction؛ هذه الدالة تنفذ SQL فقط.
  Future<void> _importContentFromTempDb(
      DatabaseExecutor db, String tmpPath) async {
    final asset = await openReadOnlyDatabase(tmpPath);
    try {
      for (final table in _contentTables) {
        await _copyTableFromAsset(db, asset, table);
      }
      for (final fts in _contentFtsTables) {
        for (final suffix in [
          '_data',
          '_idx',
          '_content',
          '_docsize',
          '_config'
        ]) {
          await _copyTableFromAsset(db, asset, '$fts$suffix');
        }
      }
    } finally {
      await asset.close();
    }
  }

  /// ينسخ جدول محتوى واحد من الأصول: الأعمدة المشتركة بين النسختين
  /// فقط (فأصول v1 بلا أعمدة v2 الجديدة تُنسخ دون كسر). يُتخطى
  /// الجدول بهدوء إن غاب من أي من النسختين. نسخ الصفوف (لا إعادة
  /// بناء FTS) يحفظ فهرس الباني المطبَّع كما هو.
  Future<void> _copyTableFromAsset(
      DatabaseExecutor db, Database asset, String table) async {
    final inAsset = await _tableExists(asset, table);
    final inMain = await _tableExists(db, table);
    if (!inAsset || !inMain) return;
    final mainCols = await _columnsOf(db, 'main', table);
    final assetCols = await _columnsOf(asset, 'main', table);
    final cols = mainCols.where(assetCols.contains).toList();
    if (cols.isEmpty) return;
    final rows = await asset.query(table, columns: cols);
    await db.delete(table);
    for (final row in rows) {
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    return _tableExistsIn(db, 'main', table);
  }

  Future<bool> _tableExistsIn(
      DatabaseExecutor db, String schema, String table) async {
    try {
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM $schema.sqlite_master "
        "WHERE type = 'table' AND name = ?",
        [table],
      );
      return ((rows.first['c'] as int?) ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _columnsOf(
      DatabaseExecutor db, String schema, String table) async {
    try {
      final rows = await db.rawQuery('PRAGMA $schema.table_info("$table")');
      return rows.map((r) => r['name'] as String).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _setMeta(DatabaseExecutor db, String key, String value) async {
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> meta(String key) async {
    final d = await db;
    final rows = await d.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return '';
    return (rows.first['value'] ?? '') as String;
  }

  // ── Search (FTS5) ──
  /// Runs an FTS5 search with a three-stage fallback so natural questions
  /// work: strict AND of the meaningful terms first, then OR across them,
  /// then the single longest term. Never throws: a bad query returns [].
  Future<List<Map<String, Object?>>> _ftsSearch(
      String table, String fts, String q, int limit) async {
    final d = await db;
    final terms = queryTerms(q);
    if (terms.isEmpty) return [];
    final sql = 'SELECT t.* FROM $table t JOIN $fts f ON f.rowid = t.id '
        'WHERE $fts MATCH ? ORDER BY rank LIMIT ?';
    try {
      var rows = await d.rawQuery(sql, [_andExpr(terms), limit]);
      if (rows.isEmpty && terms.length > 1) {
        rows = await d.rawQuery(sql, [_orExpr(terms), limit]);
      }
      if (rows.isEmpty) {
        final longest = terms.reduce((a, b) => a.length >= b.length ? a : b);
        rows = await d.rawQuery(sql, [_termGroup(longest), limit]);
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  Future<List<Article>> searchArticles(String q, {int limit = 20}) async {
    final rows = await _ftsSearch('articles', 'articles_fts', q, limit);
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Country>> searchCountries(String q, {int limit = 20}) async {
    final rows = await _ftsSearch('countries', 'countries_fts', q, limit);
    return rows.map(Country.fromMap).toList();
  }

  Future<List<TemplateDoc>> searchTemplates(String q, {int limit = 20}) async {
    final rows = await _ftsSearch('templates', 'templates_fts', q, limit);
    return rows.map(TemplateDoc.fromMap).toList();
  }

  // ── Knowledge base (kb_topics, v2) ──
  /// هل جدول مواضيع الكتاب موجود؟ false في قواعد v1 القديمة.
  Future<bool> get kbAvailable async {
    final d = await db;
    return _tableExists(d, 'kb_topics');
  }

  /// عدد مواضيع الكتاب (54 عند اكتمال قاعدة المعرفة)؛ 0 عند غياب الجدول.
  Future<int> kbTopicCount() async {
    final d = await db;
    try {
      final rows = await d.rawQuery('SELECT COUNT(*) AS c FROM kb_topics');
      return (rows.first['c'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// بحث FTS5 في مواضيع الكتاب بالمراحل الثلاث نفسها (AND ثم OR ثم
  /// أطول مصطلح). لا يرمي أبداً: قاعدة قديمة بلا الجدول تعيد [].
  /// ملاحظة: الربط هنا على t.rowid لأن معرّف الموضوع نصي (TEXT)،
  /// بخلاف _ftsSearch الذي يربط على t.id الرقمي.
  Future<List<KbTopic>> searchKbTopics(String q, {int limit = 20}) async {
    final d = await db;
    final terms = queryTerms(q);
    if (terms.isEmpty) return [];
    const sql = 'SELECT t.* FROM kb_topics t JOIN kb_topics_fts f '
        'ON f.rowid = t.rowid WHERE kb_topics_fts MATCH ? '
        'ORDER BY rank LIMIT ?';
    try {
      var rows = await d.rawQuery(sql, [_andExpr(terms), limit]);
      if (rows.isEmpty && terms.length > 1) {
        rows = await d.rawQuery(sql, [_orExpr(terms), limit]);
      }
      if (rows.isEmpty) {
        final longest = terms.reduce((a, b) => a.length >= b.length ? a : b);
        rows = await d.rawQuery(sql, [_termGroup(longest), limit]);
      }
      return rows.map(KbTopic.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  Future<KbTopic?> topicById(String id) async {
    final d = await db;
    try {
      final rows = await d.query('kb_topics', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return KbTopic.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  // ── Articles ──
  Future<List<String>> sections() async {
    final d = await db;
    final rows = await d
        .rawQuery('SELECT DISTINCT section FROM articles ORDER BY MIN(id)');
    return rows.map((r) => r['section'] as String).toList();
  }

  Future<List<Article>> articlesBySection(String section) async {
    final d = await db;
    final rows = await d.query('articles',
        where: 'section = ?', whereArgs: [section], orderBy: 'id');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> latestArticles({int limit = 6}) async {
    final d = await db;
    final rows = await d.query('articles', orderBy: 'id DESC', limit: limit);
    return rows.map(Article.fromMap).toList();
  }

  Future<Article?> articleById(int id) async {
    final d = await db;
    final rows = await d.query('articles', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Article.fromMap(rows.first);
  }

  // ── Countries ──
  Future<List<Country>> allCountries() async {
    final d = await db;
    final rows = await d.query('countries', orderBy: 'name_ar');
    return rows.map(Country.fromMap).toList();
  }

  Future<Country?> countryById(int id) async {
    final d = await db;
    final rows = await d.query('countries', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Country.fromMap(rows.first);
  }

  Future<List<NationalDayItem>> upcomingNationalDays({int days = 30}) async {
    final d = await db;
    final rows = await d
        .rawQuery('SELECT n.country_id, n.mmdd, n.name, c.name_ar, c.flag '
            'FROM national_days n JOIN countries c ON c.id = n.country_id');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <NationalDayItem>[];
    for (final r in rows) {
      final mmdd = (r['mmdd'] as String).split('-');
      final month = int.parse(mmdd[0]);
      final day = int.parse(mmdd[1]);
      var next = DateTime(now.year, month, day);
      if (next.isBefore(today)) next = DateTime(now.year + 1, month, day);
      if (next.difference(today).inDays <= days) {
        out.add(NationalDayItem(
            r['country_id'] as int,
            r['mmdd'] as String,
            r['name'] as String,
            r['name_ar'] as String,
            r['flag'] as String,
            next));
      }
    }
    out.sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return out;
  }

  // ── Templates ──
  Future<List<TemplateDoc>> allTemplates() async {
    final d = await db;
    final rows = await d.query('templates', orderBy: 'id');
    return rows.map(TemplateDoc.fromMap).toList();
  }

  Future<TemplateDoc?> templateByKey(String key) async {
    final d = await db;
    final rows = await d.query('templates', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return TemplateDoc.fromMap(rows.first);
  }

  // ── Favorites ──
  Future<bool> isFav(String kind, int refId) async {
    final d = await db;
    final rows = await d.query('favorites',
        where: 'kind = ? AND ref_id = ?', whereArgs: [kind, refId]);
    return rows.isNotEmpty;
  }

  Future<void> toggleFav(String kind, int refId) async {
    final d = await db;
    if (await isFav(kind, refId)) {
      await d.delete('favorites',
          where: 'kind = ? AND ref_id = ?', whereArgs: [kind, refId]);
    } else {
      await d.insert('favorites', {
        'kind': kind,
        'ref_id': refId,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Article>> favArticles() async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT a.* FROM articles a JOIN favorites f ON f.ref_id = a.id '
        "WHERE f.kind = 'article' ORDER BY f.created_at DESC");
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Country>> favCountries() async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT c.* FROM countries c JOIN favorites f ON f.ref_id = c.id '
        "WHERE f.kind = 'country' ORDER BY f.created_at DESC");
    return rows.map(Country.fromMap).toList();
  }

  // ── Settings ──
  Future<String> getSetting(String key, String def) async {
    final d = await db;
    final rows = await d.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return def;
    return (rows.first['value'] ?? def) as String;
  }

  Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Events ──
  Future<int> insertEvent(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('events', values);
  }

  Future<List<EventItem>> allEvents() async {
    final d = await db;
    final rows = await d.query('events', orderBy: 'date ASC');
    return rows.map(EventItem.fromMap).toList();
  }

  Future<EventItem?> eventById(int id) async {
    final d = await db;
    final rows = await d.query('events', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return EventItem.fromMap(rows.first);
  }

  Future<void> deleteEvent(int id) async {
    final d = await db;
    await d.delete('event_guests', where: 'event_id = ?', whereArgs: [id]);
    await d.delete('event_program', where: 'event_id = ?', whereArgs: [id]);
    await d.delete('checklist_items', where: 'event_id = ?', whereArgs: [id]);
    await d.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> eventGuests(int eventId) async {
    final d = await db;
    return d.query('event_guests',
        where: 'event_id = ?', whereArgs: [eventId], orderBy: 'sort_order ASC');
  }

  Future<int> insertEventGuest(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('event_guests', values);
  }

  Future<void> deleteEventGuest(int id) async {
    final d = await db;
    await d.delete('event_guests', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> eventProgram(int eventId) async {
    final d = await db;
    return d.query('event_program',
        where: 'event_id = ?', whereArgs: [eventId], orderBy: 'sort_order ASC');
  }

  Future<int> insertProgramItem(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('event_program', values);
  }

  Future<void> deleteProgramItem(int id) async {
    final d = await db;
    await d.delete('event_program', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> checklist(int eventId) async {
    final d = await db;
    return d.query('checklist_items',
        where: 'event_id = ?', whereArgs: [eventId], orderBy: 'sort_order ASC');
  }

  Future<int> insertChecklistItem(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('checklist_items', values);
  }

  Future<void> setChecklistDone(int id, bool done) async {
    final d = await db;
    await d.update('checklist_items', {'done': done ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteChecklistItem(int id) async {
    final d = await db;
    await d.delete('checklist_items', where: 'id = ?', whereArgs: [id]);
  }

  // ── Seating plans ──
  Future<int> insertPlan(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('seating_plans', values);
  }

  Future<List<SeatingPlan>> allPlans() async {
    final d = await db;
    final rows = await d.query('seating_plans', orderBy: 'updated_at DESC');
    return rows.map(SeatingPlan.fromMap).toList();
  }

  Future<void> updatePlan(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('seating_plans', values,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> planAssignments(int planId) async {
    final d = await db;
    return d.query('seating_assignments',
        where: 'plan_id = ?', whereArgs: [planId], orderBy: 'seat_index ASC');
  }

  /// إعادة حفظ التعيينات بحذف+إدراج داخل Transaction واحدة: فشل
  /// المنتصف يتراجع كاملاً فلا يُفقد المخطط (عيب V2_PLAN §1.2).
  Future<void> saveAssignments(
      int planId, List<Map<String, Object?>> assignments) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('seating_assignments',
          where: 'plan_id = ?', whereArgs: [planId]);
      for (final a in assignments) {
        await txn.insert('seating_assignments', {'plan_id': planId, ...a});
      }
      await txn.update(
          'seating_plans', {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [planId]);
    });
  }

  Future<void> deletePlan(int id) async {
    final d = await db;
    await d
        .delete('seating_assignments', where: 'plan_id = ?', whereArgs: [id]);
    await d.delete('seating_plans', where: 'id = ?', whereArgs: [id]);
  }

  // ── Delegations (إدارة الوفود — أداة مستقلة، V2_PLAN §1.2/7) ──
  Future<int> insertDelegation(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('delegations', values);
  }

  Future<List<Map<String, Object?>>> allDelegations() async {
    final d = await db;
    return d.query('delegations', orderBy: 'updated_at DESC');
  }

  Future<Map<String, Object?>?> delegationById(int id) async {
    final d = await db;
    final rows =
        await d.query('delegations', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateDelegation(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('delegations', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteDelegation(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('delegation_members',
          where: 'delegation_id = ?', whereArgs: [id]);
      await txn.delete('conference_delegations',
          where: 'delegation_id = ?', whereArgs: [id]);
      await txn.delete('delegations', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> delegationMembers(int delegationId) async {
    final d = await db;
    return d.query('delegation_members',
        where: 'delegation_id = ?',
        whereArgs: [delegationId],
        orderBy: 'sort_order ASC');
  }

  Future<int> insertDelegationMember(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('delegation_members', values);
  }

  Future<void> updateDelegationMember(
      int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('delegation_members', values,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteDelegationMember(int id) async {
    final d = await db;
    await d.delete('delegation_members', where: 'id = ?', whereArgs: [id]);
  }

  // ── Visits (الزيارات الدبلوماسية — أداة مستقلة، V2_PLAN §1.2/3) ──
  Future<int> insertVisit(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('visits', values);
  }

  Future<List<Map<String, Object?>>> allVisits() async {
    final d = await db;
    return d.query('visits', orderBy: 'updated_at DESC');
  }

  Future<Map<String, Object?>?> visitById(int id) async {
    final d = await db;
    final rows = await d.query('visits', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateVisit(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('visits', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteVisit(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('visit_items', where: 'visit_id = ?', whereArgs: [id]);
      await txn.delete('visits', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> visitItems(int visitId) async {
    final d = await db;
    return d.query('visit_items',
        where: 'visit_id = ?', whereArgs: [visitId], orderBy: 'sort_order ASC');
  }

  Future<int> insertVisitItem(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('visit_items', values);
  }

  Future<void> updateVisitItem(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('visit_items', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteVisitItem(int id) async {
    final d = await db;
    await d.delete('visit_items', where: 'id = ?', whereArgs: [id]);
  }

  // ── Conferences (تنظيم المؤتمرات — أداة مستقلة، V2_PLAN §1.2/4) ──
  Future<int> insertConference(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('conferences', values);
  }

  Future<List<Map<String, Object?>>> allConferences() async {
    final d = await db;
    return d.query('conferences', orderBy: 'updated_at DESC');
  }

  Future<Map<String, Object?>?> conferenceById(int id) async {
    final d = await db;
    final rows =
        await d.query('conferences', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateConference(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('conferences', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteConference(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('conference_sessions',
          where: 'conference_id = ?', whereArgs: [id]);
      await txn.delete('conference_delegations',
          where: 'conference_id = ?', whereArgs: [id]);
      await txn.delete('conferences', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> conferenceSessions(int conferenceId) async {
    final d = await db;
    return d.query('conference_sessions',
        where: 'conference_id = ?',
        whereArgs: [conferenceId],
        orderBy: 'sort_order ASC');
  }

  Future<int> insertConferenceSession(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('conference_sessions', values);
  }

  Future<void> updateConferenceSession(
      int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('conference_sessions', values,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteConferenceSession(int id) async {
    final d = await db;
    await d.delete('conference_sessions', where: 'id = ?', whereArgs: [id]);
  }

  /// الوفود المشاركة في المؤتمر (مع اسم الوفد ودولته).
  Future<List<Map<String, Object?>>> conferenceDelegations(
      int conferenceId) async {
    final d = await db;
    return d.rawQuery(
        'SELECT cd.id AS link_id, dg.* FROM conference_delegations cd '
        'JOIN delegations dg ON dg.id = cd.delegation_id '
        'WHERE cd.conference_id = ? ORDER BY dg.name',
        [conferenceId]);
  }

  Future<void> addDelegationToConference(
      int conferenceId, int delegationId) async {
    final d = await db;
    await d.insert('conference_delegations',
        {'conference_id': conferenceId, 'delegation_id': delegationId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeDelegationFromConference(int linkId) async {
    final d = await db;
    await d.delete('conference_delegations',
        where: 'id = ?', whereArgs: [linkId]);
  }

  // ── Banquets (المآدب الرسمية — أداة مستقلة، V2_PLAN §1.2/5) ──
  Future<int> insertBanquet(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('banquets', values);
  }

  Future<List<Map<String, Object?>>> allBanquets() async {
    final d = await db;
    return d.query('banquets', orderBy: 'updated_at DESC');
  }

  Future<Map<String, Object?>?> banquetById(int id) async {
    final d = await db;
    final rows = await d.query('banquets', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateBanquet(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('banquets', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBanquet(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('banquet_guests',
          where: 'banquet_id = ?', whereArgs: [id]);
      await txn.delete('banquet_items',
          where: 'banquet_id = ?', whereArgs: [id]);
      await txn.delete('banquets', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> banquetGuests(int banquetId) async {
    final d = await db;
    return d.query('banquet_guests',
        where: 'banquet_id = ?',
        whereArgs: [banquetId],
        orderBy: 'sort_order ASC');
  }

  Future<int> insertBanquetGuest(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('banquet_guests', values);
  }

  Future<void> updateBanquetGuest(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('banquet_guests', values,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBanquetGuest(int id) async {
    final d = await db;
    await d.delete('banquet_guests', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> banquetItems(int banquetId) async {
    final d = await db;
    return d.query('banquet_items',
        where: 'banquet_id = ?',
        whereArgs: [banquetId],
        orderBy: 'sort_order ASC');
  }

  Future<int> insertBanquetItem(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('banquet_items', values);
  }

  Future<void> updateBanquetItem(int id, Map<String, Object?> values) async {
    final d = await db;
    await d.update('banquet_items', values,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBanquetItem(int id) async {
    final d = await db;
    await d.delete('banquet_items', where: 'id = ?', whereArgs: [id]);
  }

  // ── Saved chats (المحادثات المحفوظة — CHARTER_V2 §4.6) ──
  // الحفظ تلقائي من المساعد؛ لا بيانات تغادر الجهاز أبداً.
  Future<int> insertChatConversation(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('chat_conversations', values);
  }

  Future<int> insertChatMessage(Map<String, Object?> values) async {
    final d = await db;
    return d.insert('chat_messages', values);
  }

  /// المحادثات مع عدد رسائل كل منها، الأحدث أولاً.
  Future<List<Map<String, Object?>>> allChatConversations() async {
    final d = await db;
    return d.rawQuery(
        'SELECT c.*, COUNT(m.id) AS msg_count FROM chat_conversations c '
        'LEFT JOIN chat_messages m ON m.conversation_id = c.id '
        'GROUP BY c.id ORDER BY c.updated_at DESC');
  }

  Future<Map<String, Object?>?> chatConversationById(int id) async {
    final d = await db;
    final rows = await d
        .query('chat_conversations', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> chatMessages(int conversationId) async {
    final d = await db;
    return d.query('chat_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'id ASC');
  }

  Future<void> touchChatConversation(int id) async {
    final d = await db;
    await d.update('chat_conversations',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteChatConversation(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('chat_messages',
          where: 'conversation_id = ?', whereArgs: [id]);
      await txn.delete('chat_conversations',
          where: 'id = ?', whereArgs: [id]);
    });
  }
}
