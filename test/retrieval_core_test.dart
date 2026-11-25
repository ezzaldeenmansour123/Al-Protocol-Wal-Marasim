// ignore_for_file: avoid_print
// اختبار طبقة الاسترجاع المحلية (lib/ai/retrieval_core.dart).
//
// سكربت Dart مستقل: main() مع asserts فقط، بلا flutter_test، حتى
// يُشغَّل مباشرة بـ `dart`:
//   dart test/retrieval_core_test.dart
// (يُشغَّل أيضاً من CI عبر الغلاف test/retrieval_core_flutter_test.dart).
// يطبع تعبيرات FTS5 المولَّدة حتى يمكن التحقق منها مقابل قاعدة
// اختبار SQLite (انظر docs/RAG_PHASE2.md).

import 'package:protocol_marasim/ai/retrieval_core.dart';

int _passed = 0;

void check(bool ok, String name) {
  assert(ok, name);
  if (!ok) throw StateError('FAIL: $name');
  _passed++;
  print('  PASS: $name');
}

void main() {
  print('retrieval_core_test — pure Dart, no flutter_test');

  // ── 1. التطبيع العربي ──
  print('1) normalizeAr');
  check(normalizeAr('الْمَرَاسِمُ') == 'المراسم', 'تشكيل يُزال');
  check(normalizeAr('إأآٱ') == 'اااا', 'أشكال الألف توحَّد');
  check(normalizeAr('مُعاهدة') == 'معاهده', 'تاء مربوطة → هاء');
  check(normalizeAr('موسى') == 'موسي', 'ألف مقصورة → ياء');
  check(normalizeAr('البروتوكولُ، والمراسم!') == 'البروتوكول والمراسم',
      'ترقيم يُستبدل بفراغ وتوحيد فراغات');
  check(normalizeAr('  زيارة   رسمية  ') == 'زياره رسميه',
      'فراغات زائدة + تاء مربوطة');
  check(normalizeAr('و\u0670') == 'ا', 'ألف خنجرية (وٓ) → ألف');
  check(normalizeAr('') == '', 'سلسلة فارغة');

  // ── 2. إزالة كلمات التوقف ──
  print('2) queryTerms');
  check(
      queryTerms('كيف أرتب جلوس وفد يضم خمس دول؟').join(' ') == 'جلوس وفد دول',
      'كلمات توقف تُزال (كيف/أرتب/يضم/خمس) وتبقى المصطلحات ذات المعنى');
  check(queryTerms('ما الأسبقية؟').join(' ') == 'الاسبقيه',
      'سؤال قصير يبقي مصطلحه الوحيد');
  check(queryTerms('كيف؟').join(' ') == 'كيف',
      'سؤال من كلمات توقف فقط يعود إلى كل المصطلحات');
  check(queryTerms('تعريف البروتوكولات').join(' ') == 'تعريف البروتوكولات',
      'بلا كلمات توقف: تبقى كما هي');

  // ── 3. تعبير FTS5 ──
  print('3) FTS5 expressions');
  final andExpr = ftsAndExpression(['اسبقيه', 'دول']);
  print('  AND: $andExpr');
  check(andExpr.contains('"اسبقيه"*') && andExpr.contains(' AND '),
      'AND يجمع المصطلحات');
  check(andExpr.contains('"الاسبقيه"*'), 'مصطلح بلا ال يطابق مع ال');
  final group = ftsTermGroup('وفد');
  print('  group(وفد): $group');
  check(group.contains('"وفد"*') && group.contains('"وفود"*'),
      'مفرد/جمع يُربطان بـ OR');
  check(group.contains('"الوفد"*'), 'بادئة ال تُضاف');
  final groupAl = ftsTermGroup('الاسبقيه');
  print('  group(الاسبقيه): $groupAl');
  check(groupAl.contains('"اسبقيه"*'), 'مصطلح بأل يطابق بدونها');
  final orExpr = ftsOrExpression(['اسبقيه', 'دول']);
  check(orExpr.contains(' OR ') && !orExpr.contains(' AND '), 'OR بلا AND');
  check(ftsLongestTermExpression(['ا', 'الاسبقيه']).contains('الاسبقيه'),
      'أطول مصطلح يُختار للمرحلة الأخيرة');
  final stages = ftsMatchStages('ترتيب الأسبقية في حفل استقبال رسمي');
  print('  stages:');
  for (final s in stages) {
    print('    $s');
  }
  check(stages.length == 3, 'ثلاث مراحل: AND ثم OR ثم أطول مصطلح');
  check(stages[0].contains(' AND ') && stages[1].contains(' OR '),
      'ترتيب المراحل صحيح');
  check(ftsMatchStages('الأسبقية').length == 1, 'مصطلح واحد: مرحلة واحدة فقط');
  check(ftsMatchStages('').isEmpty, 'سؤال فارغ: بلا مراحل');

  // ── 4. قرار الرفض ──
  print('4) evaluateRetrieval (refusal decision)');
  final noResults = evaluateRetrieval(
    const [],
    queryTermCount: 3,
    kbAvailable: true,
  );
  check(noResults.refused && noResults.reason == 'no_results',
      'صفر نتائج → رفض no_results');
  check(noResults.top == null, 'لا مقطع أعلى عند الرفض');
  const weakSingle = RetrievedChunk(
    topicId: 'P2C1-M2-01',
    title: 'الأسبقية داخل الدولة',
    excerpt: 'قواعد الأسبقية داخل الدولة.',
    source: 'كتاب «البروتوكول والمراسم»',
    rankScore: -0.4,
    matchedTerms: 1,
  );
  final weak = evaluateRetrieval(
    const [weakSingle],
    queryTermCount: 3,
    kbAvailable: true,
  );
  check(weak.refused && weak.reason == 'weak_relevance',
      'نتيجة واحدة ضعيفة لسؤال مركب → رفض weak_relevance');
  const strongSingle = RetrievedChunk(
    topicId: 'P1C1-M3',
    title: 'تعريف التشريفات',
    excerpt: 'التشريفات هي …',
    source: 'كتاب «البروتوكول والمراسم»',
    rankScore: -2.1,
    matchedTerms: 1,
  );
  final singleTerm = evaluateRetrieval(
    const [strongSingle],
    queryTermCount: 1,
    kbAvailable: true,
  );
  check(!singleTerm.refused && singleTerm.top?.topicId == 'P1C1-M3',
      'سؤال بمصطلح واحد مع نتيجة واحدة قوية → قبول');
  final multi = evaluateRetrieval(
    const [weakSingle, strongSingle],
    queryTermCount: 3,
    kbAvailable: true,
  );
  check(!multi.refused && multi.chunks.length == 2,
      'عدة نتائج → قبول ويُعرض أعلاها صلة');
  check(multi.related.length == 1 && multi.related.first.topicId == 'P1C1-M3',
      'related = الباقي بعد الأعلى');
  final kbMissing = evaluateRetrieval(
    const [],
    queryTermCount: 2,
    kbAvailable: false,
  );
  check(kbMissing.refused && !kbMissing.kbAvailable,
      'غياب جدول kb_topics يُسجَّل في النتيجة (kbAvailable=false)');
  check(
      refusalText ==
          'لا تتوفر في قاعدة المعرفة الحالية معلومات موثوقة وكافية للإجابة عن هذا السؤال.',
      'نص الرفض حرفي ثابت');

  // ── 5. بناء RetrievedChunk مع الصفحة ──
  print('5) RetrievedChunk + pages');
  const chunk = RetrievedChunk(
    topicId: 'P2C1-M2-06',
    title: 'الأسبقية في جامعة الدول العربية',
    part: 'الباب الثاني',
    chapter: 'الفصل الأول: إدارة المراسم والبروتوكول الرسمي في الدولة',
    mabhas: 'المبحث الثاني',
    excerpt: 'تستند الأسبقية في جامعة الدول العربية إلى مبدأ المساواة …',
    bookPageStart: 75,
    bookPageEnd: 80,
    source: 'كتاب «البروتوكول والمراسم»',
    sourceType: 'كتاب',
    textStatus: 'مصحح آلياً',
    rankScore: -3.2,
    matchedTerms: 3,
  );
  check(chunk.hasBookPages, 'hasBookPages مع صفحتين');
  check(chunk.bookPagesLabel == 'ص. 75–80', 'تسمية الصفحات ص. X–Y');
  check(chunk.citationLine == 'المصدر: كتاب «البروتوكول والمراسم» — ص. 75–80',
      'سطر الاستشهاد الكامل');
  const frontMatter = RetrievedChunk(
    topicId: 'FM-01',
    title: 'المادة الافتتاحية',
    excerpt: '…',
    bookPageLabel: 'بلا ترقيم مطبوع؛ الإهداء «أ»',
    source: 'كتاب «البروتوكول والمراسم»',
  );
  check(!frontMatter.hasBookPages, 'المادة الافتتاحية بلا صفحات مطبوعة');
  check(frontMatter.bookPagesLabel == 'بلا ترقيم مطبوع؛ الإهداء «أ»',
      'تسمية الصفحة البديلة تُعرض عند غياب الترقيم');

  // ── 6. المقتطف وعدّ المصطلحات ──
  print('6) buildExcerpt + countMatchedTerms');
  check(
      buildExcerpt(
              definition: 'التعريف.',
              explanation: 'الشرح.',
              summary: 'الملخص.') ==
          'التعريف.',
      'التعريف يتقدم على الشرح والملخص');
  check(buildExcerpt(explanation: 'الشرح.', summary: 'الملخص.') == 'الشرح.',
      'عند غياب التعريف يأتي الشرح');
  check(buildExcerpt(summary: 'الملخص.') == 'الملخص.',
      'عند غياب التعريف والشرح يأتي الملخص');
  check(buildExcerpt() == '', 'غياب كل الحقول → مقتطف فارغ');
  final long = buildExcerpt(summary: 'أ' * 700);
  check(long.length == maxExcerptLength + 1 && long.endsWith('…'),
      'مقتطف طويل يُقصّ مع …');
  final terms = queryTerms('ترتيب الأسبقية في حفل استقبال');
  check(
      countMatchedTerms(
              'قواعد ترتيب الأسبقية في حفلات الاستقبال الرسمية', terms) >=
          3,
      'عدّ المصطلحات المطابقة في النص');
  check(countMatchedTerms('موضوع عن المآدب', terms) == 0,
      'نص بلا مصطلحات مطابقة → صفر');

  // ── 7. ترجيح العنوان (R1 — F1) ──
  print('7) countTitleMatchedTerms (title-first ranking)');
  check(
      countTitleMatchedTerms(
        'مراسم استقبال كبار الشخصيات',
        ['استقبال', 'شخصيات', 'مطار'],
        enKeywords: 'reception arrival airport',
        arKeywords: 'مطار وصول',
      ) ==
          3,
      'عنوان يطابق 3 مصطلحات (استقبال/شخصيات من العنوان، مطار من المفردات)');
  check(
      countTitleMatchedTerms(
        'مراسم الأعلام والنشيد والشعار الوطني',
        ['flag', 'anthem', 'emblem'],
        enKeywords: 'flag flags anthem anthems emblem emblems national',
      ) ==
          3,
      'مصطلحات إنجليزية تطابق مفردات الفهرس الإنجليزية');
  check(
      countTitleMatchedTerms('نشأة البروتوكولات الدبلوماسية الحديثة',
              ['vienna', 'congress'],
              enKeywords: 'vienna congress 1815') ==
          2,
      'مصطلحات إنجليزية تطابق مفردات العنوان الإنجليزية');
  check(
      countTitleMatchedTerms('نشأة البروتوكولات الدبلوماسية الحديثة',
              ['فيينا', 'فيينا', 'مؤتمر'],
              arKeywords: 'فيينا مؤتمر تطور') ==
          2,
      'المصطلح العربي المكرر في السؤال يُحسب مرة واحدة');
  check(
      countTitleMatchedTerms('تعريف التشريفات', ['تشريفات', 'هدف'],
              arKeywords: 'هدف استقبال') ==
          2,
      'مفردة عربية من نص الموضوع تُحسب في العنوان');
  check(ftsFetchLimit == 20, 'يُجلب 20 مرشحاً قبل إعادة الترتيب');

  // ── 8. كلمات التوقف الإنجليزية والتجريد الصرفي (R1) ──
  print('8) English stopwords + morphology');
  check(normalizeAr('What Is Protocol?') == 'what is protocol',
      'تصغير الأحرف اللاتينية في التطبيع');
  check(
      queryTerms('What is protocol in international relations?').join(' ') ==
          'protocol international relations',
      'كلمات توقف إنجليزية تُزال (what/is/in)');
  check(
      queryTerms('What ceremonies surround national flags, anthems and emblems?')
              .join(' ') ==
          'ceremonies surround national flags anthems emblems',
      'سؤال إنجليزي يبقي مصطلحاته ذات المعنى');
  check(ftsTermGroup('المطار').contains('"وصول"*'),
      'المطار يطابق وصول عبر الصيغة المجرّدة من ال');
  check(ftsTermGroup('استقباله').contains('"استقبال"*'),
      'لاحقة الضمير تُجرَّد (استقباله → استقبال)');
  check(
      ftsTermGroup('سفيران').contains('"سفير"*') &&
          ftsTermGroup('سفيران').contains('"سفراء"*'),
      'المثنى يُجرَّد (سفيران → سفير/سفراء)');
  check(!ftsTermGroup('وما').contains('"ما"*'),
      'المتغير الذي هو كلمة توقف يُسقَط (وما لا تولّد ما)');
  check(!ftsTermGroup('كلمه').contains('"مه"*'),
      'لا تجريد متسلسل للبوادئ (كلمه لا تولّد مه)');
  check(termVariants('وفد').contains('ضيف'),
      'وفد يطابق ضيف (مرادف موضعي)');
  check(termVariants('ceremony').contains('ceremonies'),
      'جمع إنجليزي لا يربطه البادئ (ceremony/ceremonies)');
  check(
      countMatchedTerms('مراسم استقبال الوفود في المطار',
              queryTerms('ما إجراءات استقبال وفد رسمي في المطار؟')) ==
          3,
      'عدّ المصطلحات يستخدم المتغيرات الصرفية (وفد→وفود)');

  print('ALL PASSED ($_passed checks)');
}
