// اختبار موجهات التوليد المقيّد بالاسترجاع (lib/ai/prompts.dart).
//
// سكربت Dart مستقل: main() مع asserts فقط، بلا flutter_test، حتى
// يُشغَّل مباشرة بـ `dart`:
//   dart test/prompts_test.dart
// (يُشغَّل أيضاً من CI عبر الغلاف test/prompts_flutter_test.dart).
// يغطي: بناء كتلة السياق (عنوان + مقتطف + صفحة كتاب)، موجهات
// النظام للأساليب السبعة والأطوال الثلاثة، القواعد الصارمة، رسالة
// المستخدم مع سياق المحادثة، وقرار الرفض قبل التوليد (جملة الرفض
// حرفياً دون استدعاء النموذج). لا قاعدة بيانات ولا شبكة ولا نموذج.

import '../lib/ai/answer_style.dart';
import '../lib/ai/prompts.dart';
import '../lib/ai/retrieval_core.dart';

int _passed = 0;

void check(bool ok, String name) {
  assert(ok, name);
  if (!ok) throw StateError('FAIL: $name');
  _passed++;
  print('  PASS: $name');
}

RetrievedChunk _chunk({
  String id = 'P2C1-M2-01',
  String title = 'ترتيب الأسبقية في حفل الاستقبال',
  String excerpt = 'يتقدم السفراء بحسب تاريخ تقديم أوراق الاعتماد.',
  int? start = 45,
  int? end = 48,
  String source = 'كتاب «البروتوكول والمراسم»',
}) =>
    RetrievedChunk(
      topicId: id,
      title: title,
      excerpt: excerpt,
      bookPageStart: start,
      bookPageEnd: end,
      source: source,
    );

void main() {
  print('prompts_test — pure Dart, no flutter_test');

  // ── 1. كتلة السياق ──
  print('1) buildContextBlock');
  final chunks = [_chunk(), _chunk(id: 'P2C1-M2-02', title: 'ترتيب الأعلام')];
  final block = buildContextBlock(chunks);
  check(block.contains('ترتيب الأسبقية في حفل الاستقبال'), 'P01: العنوان في الكتلة');
  check(block.contains('يتقدم السفراء بحسب تاريخ تقديم أوراق الاعتماد.'),
      'P02: المقتطف في الكتلة');
  check(block.contains('ص. 45–48'), 'P03: رقم صفحة الكتاب في الكتلة');
  check(block.contains('كتاب «البروتوكول والمراسم»'), 'P04: المصدر في الكتلة');
  check(block.contains('[المصدر 1]') && block.contains('[المصدر 2]'),
      'P05: ترقيم المصادر');
  check(buildContextBlock(const []).contains('لا توجد مقاطع مسترجعة'),
      'P06: بلا مقاطع — علامة صريحة لا محتوى مخترع');
  final noPages = _chunk(start: null, end: null);
  check(!buildContextBlock([noPages]).contains('ص. '),
      'P07: مقطع بلا صفحات لا يُنسب إليه رقم صفحة');
  final many = List.generate(8, (i) => _chunk(id: 'T$i', title: 'موضوع $i'));
  final capped = buildContextBlock(many);
  check(capped.contains('موضوع 5') && !capped.contains('موضوع 6'),
      'P08: الكتلة تقف عند $maxRagChunks مقاطع');

  // ── 2. توجيهات الأسلوب (السبعة) ──
  print('2) styleDirective — all 7 styles');
  final directives = <String>{};
  for (final style in AnswerStyle.values) {
    final d = styleDirective(style);
    check(d.isNotEmpty, 'P09: توجيه غير فارغ لـ $style');
    directives.add(d);
  }
  check(directives.length == 7, 'P10: توجيه مميز لكل أسلوب من السبعة');
  check(styleDirective(AnswerStyle.concise).contains('مختصر'),
      'P11: المختصر يطلب الإيجاز');
  check(styleDirective(AnswerStyle.academic).contains('أكاديمي'),
      'P12: الأكاديمي يطلب المنهجية');

  // ── 3. توجيهات الطول (الثلاثة) ──
  print('3) lengthDirective — 3 lengths');
  check(lengthDirective(AnswerLength.short) !=
          lengthDirective(AnswerLength.medium),
      'P13: القصير يختلف عن المتوسط');
  check(lengthDirective(AnswerLength.detailed) !=
          lengthDirective(AnswerLength.short),
      'P14: المفصل يختلف عن القصير');
  check(maxTokensForLength(AnswerLength.short) <
          maxTokensForLength(AnswerLength.medium) &&
      maxTokensForLength(AnswerLength.medium) <
          maxTokensForLength(AnswerLength.detailed),
      'P15: رموز الطول متدرجة short < medium < detailed');

  // ── 4. موجه النظام الكامل ──
  print('4) buildSystemPrompt');
  for (final style in AnswerStyle.values) {
    final prompt = buildSystemPrompt(
      style: style,
      length: AnswerLength.medium,
      chunks: chunks,
    );
    check(prompt.contains('لا تجب إلا من المقاطع المعطاة'),
        'P16: قاعدة عدم الاختلاق في موجه $style');
    check(prompt.contains('ص. 45–48'), 'P17: صفحات الكتاب في موجه $style');
    check(prompt.contains('من الكتاب') && prompt.contains('تحليل واقتراح عملي'),
        'P18: تمييز معلومات الكتاب عن التحليل في موجه $style');
    check(prompt.contains('لا تخترع أرقام مواد أو اتفاقيات'),
        'P19: منع اختراع الأرقام في موجه $style');
  }
  final shortPrompt = buildSystemPrompt(
    style: AnswerStyle.diplomatic,
    length: AnswerLength.short,
    chunks: chunks,
  );
  final detailedPrompt = buildSystemPrompt(
    style: AnswerStyle.diplomatic,
    length: AnswerLength.detailed,
    chunks: chunks,
  );
  check(shortPrompt != detailedPrompt, 'P20: الطول يغيّر موجه النظام');
  check(!shortPrompt.contains('المادة 77') &&
          !shortPrompt.contains('اتفاقية مخترعة'),
      'P21: الموجه لا يحتوي أي رقم مادة أو اتفاقية من خارج المقاطع');

  // ── 5. رسالة المستخدم وسياق المحادثة ──
  print('5) buildUserMessage');
  check(buildUserMessage(question: 'ما الأسبقية؟', history: const []) ==
          'ما الأسبقية؟',
      'P22: بلا سياق — السؤال كما هو');
  final withHistory = buildUserMessage(
    question: 'وماذا عن الأعلام؟',
    history: const [
      ChatHistoryTurn(question: 'ما الأسبقية؟', answer: 'الأسبقية حسب التاريخ.'),
    ],
  );
  check(withHistory.contains('سياق المحادثة السابقة'),
      'P23: السياق موسوم بوضوح');
  check(withHistory.contains('ما الأسبقية؟') &&
          withHistory.contains('الأسبقية حسب التاريخ.'),
      'P24: التبادل السابق في الرسالة');
  check(withHistory.contains('السؤال الحالي: وماذا عن الأعلام؟'),
      'P25: السؤال الحالي مميز عن السياق');

  // ── 6. قرار الرفض قبل التوليد ──
  print('6) ragRefusal');
  const refused = RetrievalResult(
    chunks: [],
    refused: true,
    reason: 'no_results',
    kbAvailable: true,
  );
  check(ragRefusal(refused) == refusalText,
      'P26: الرفض يعيد جملة الرفض حرفياً');
  const accepted = RetrievalResult(
    chunks: [],
    refused: false,
    kbAvailable: true,
  );
  check(ragRefusal(accepted) == null, 'P27: القبول يعيد null (يُسمح بالتوليد)');

  // ── 7. وسم الإجابة المولدة ──
  print('7) generatedAnswerTag');
  check(generatedAnswerTag.contains('مقيّد بالمقاطع'),
      'P28: وسم التوليد يصرّح بالتقييد بالمقاطع');

  print('ALL PASSED ($_passed checks)');
}
