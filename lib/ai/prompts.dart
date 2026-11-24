// موجهات التوليد المقيّد بالاسترجاع (P6 — Pure Dart فقط).
//
// تبني موجه النظام من المقاطع المسترجعة فقط: العنوان + المقتطف +
// رقم صفحة الكتاب لكل مقطع، مع تعليمات صارمة تمنع الإجابة من غير
// المقاطع المعطاة. لا تُبنى أي إجابة هنا، ولا يُنسَب للكتاب أي نص
// غير المقاطع الممرَّرة — الملف يستقبل المقاطع جاهزة من طبقة
// الاسترجاع ويعيد نصوص موجهات فقط.
//
// القاعدة الذهبية: عند رفض الاسترجاع لا يُبنى موجه ولا يُستدعى
// النموذج أبداً؛ المزود يعيد جملة الرفض حرفياً (انظر [ragRefusal]).

import 'answer_style.dart';
import 'retrieval_core.dart';

/// أقصى عدد مقاطع تُمرَّر إلى النموذج في موجه واحد.
const int maxRagChunks = 6;

/// أقصى طول لكتلة السياق (أحرف) — تُقصّ المقاطع الأبعد صلة عند
/// تجاوزه حتى لا يفيض سياق النموذج.
const int maxContextChars = 6000;

/// وسم يُلحَق بنهاية كل إجابة مولّدة محلياً: يميّز التوليد عن
/// الاقتباس الحرفي ويذكّر بالتحقق من المصادر.
const String generatedAnswerTag =
    'توليد محلي مقيّد بالمقاطع أعلاه — تحقّق من المصادر قبل الاعتماد على الإجابة.';

/// يبني كتلة السياق من المقاطع: لكل مقطع عنوانه ومقتطفه ورقم صفحة
/// الكتاب ومصدره. لا يضيف أي نص من خارج المقاطع المعطاة.
/// المقاطع بلا صفحات كتاب (مقالات احتياطية) تُوسَم بمصدرها كما هو
/// دون ادعاء صفحة كتاب لها.
String buildContextBlock(List<RetrievedChunk> chunks) {
  if (chunks.isEmpty) {
    return 'لا توجد مقاطع مسترجعة — لا تجب.';
  }
  final buffer = StringBuffer();
  var used = 0;
  for (var i = 0; i < chunks.length && i < maxRagChunks; i++) {
    final c = chunks[i];
    final pages = c.bookPagesLabel;
    final block = StringBuffer()
      ..writeln('[المصدر ${i + 1}] ${c.title}')
      ..writeln(c.excerpt)
      ..writeln(
          pages.isEmpty ? 'المصدر: ${c.source}' : 'المصدر: ${c.source} — $pages');
    if (c.textStatus.isNotEmpty) {
      block.writeln('حالة النص: ${c.textStatus}');
    }
    final text = block.toString();
    if (used + text.length > maxContextChars && i > 0) break;
    buffer
      ..writeln(text)
      ..writeln();
    used += text.length;
  }
  return buffer.toString().trim();
}

/// توجيه الأسلوب: جملة واحدة لكل أسلوب من الأساليب السبعة.
/// كل الأساليب تخضع لقواعد عدم الاختلاق نفسها؛ الأسلوب يضبط الصياغة
/// فقط، لا المحتوى ولا المصادر.
String styleDirective(AnswerStyle style) {
  switch (style) {
    case AnswerStyle.veryFormal:
      return 'الأسلوب: رسمي جداً — صياغة بروتوكولية رصينة بألفاظ المخاطبات الرسمية، بلا اختصار مخلّ ولا لهجة محكية.';
    case AnswerStyle.diplomatic:
      return 'الأسلوب: دبلوماسي — صياغة مهذبة ومتوازنة بعبارات المجاملة الدبلوماسية المعتادة، مع الدقة في الألقاب والمراتب.';
    case AnswerStyle.academic:
      return 'الأسلوب: أكاديمي — صياغة علمية منهجية بالتعريف ثم الشرح ثم الاستنتاج، مع ذكر المصدر عند كل قاعدة.';
    case AnswerStyle.administrative:
      return 'الأسلوب: إداري — صياغة إجرائية واضحة بنقاط مرقّمة وخطوات قابلة للتنفيذ مباشرة.';
    case AnswerStyle.concise:
      return 'الأسلوب: مختصر ومباشر — إجابة موجزة في صلب السؤال بلا مقدمات ولا تفاصيل ثانوية.';
    case AnswerStyle.detailed:
      return 'الأسلوب: تفصيلي وتحليلي — إجابة وافية تشرح القاعدة وأساسها وتطبيقاتها العملية مع الأمثلة الواردة في المقاطع فقط.';
    case AnswerStyle.simplified:
      return 'الأسلوب: مبسّط وتعليمي — شرح مبسط بلغة سهلة مع تعريف كل مصطلح بروتوكولي عند أول ورود له.';
  }
}

/// توجيه طول الإجابة (معامل مستقل عن الأسلوب).
String lengthDirective(AnswerLength length) {
  switch (length) {
    case AnswerLength.short:
      return 'الطول: إجابة قصيرة (فقرة أو فقرتان على الأكثر).';
    case AnswerLength.medium:
      return 'الطول: إجابة متوسطة (عدة فقرات منظمة).';
    case AnswerLength.detailed:
      return 'الطول: إجابة مفصلة (شرح وافٍ منظم بعناوين فرعية عند الحاجة).';
  }
}

/// القواعد الصارمة المشتركة لكل موجه نظام: لا إجابة إلا من المقاطع،
/// والاستشهاد بأرقام صفحات الكتاب، وتمييز معلومات الكتاب عن التحليل
/// والاقتراح العملي.
const String _groundingRules = '''
قواعد ملزمة لا يجوز مخالفتها:
1. لا تجب إلا من المقاطع المعطاة في «المقاطع المسترجعة» أدناه — لا تستخدم أي معرفة خارجية، ولا تخمّن، ولا تكمل من عندك.
2. إن لم تكفِ المقاطع للإجابة عن السؤال فقل حرفياً: «لا تتوفر في قاعدة المعرفة الحالية معلومات موثوقة وكافية للإجابة عن هذا السؤال.» ولا تضف شيئاً بعدها.
3. استشهد برقم صفحة الكتاب بعد كل قاعدة أو معلومة (مثال: «… (ص. 45–48)»)، واستخدم أرقام الصفحات الواردة في المقاطع فقط.
4. ميّز بوضوح بين قسمين: «من الكتاب» (معلومات حرفية من المقاطع مع صفحاتها) و«تحليل واقتراح عملي» (تطبيق أو ترتيب مقترح مبني على تلك المعلومات فقط، موسوم بأنه اقتراح لا قاعدة من الكتاب).
5. لا تخترع أرقام مواد أو اتفاقيات أو ألقاباً أو أسماء دول أو تواريخ — كل رقم أو اسم يجب أن يرد في المقاطع المعطاة.
6. أجب باللغة العربية ما لم يكن السؤال بالإنجليزية، وحافظ على الألقاب والمراتب كما وردت في المقاطع.
''';

/// يبني موجه النظام الكامل: القواعد الصارمة + توجيه الأسلوب +
/// توجيه الطول + كتلة المقاطع المسترجعة.
String buildSystemPrompt({
  required AnswerStyle style,
  required AnswerLength length,
  required List<RetrievedChunk> chunks,
}) {
  return 'أنت مساعد «البروتوكول والمراسم» — تجيب عن أسئلة البروتوكول الدبلوماسي والمراسم من كتاب «البروتوكول والمراسم» للباحث أسعد منصور فقط.\n\n'
      '$_groundingRules\n'
      '${styleDirective(style)}\n'
      '${lengthDirective(length)}\n\n'
      'المقاطع المسترجعة:\n${buildContextBlock(chunks)}';
}

/// يبني رسالة المستخدم المرسلة إلى النموذج: سياق المحادثة السابقة
/// (إن وُجد) موسوماً بوضوح كأسئلة وإجابات سابقة، ثم السؤال الحالي.
/// السياق هنا نص عادي داخل رسالة المستخدم، لا رسائل أدوار منفصلة.
String buildUserMessage({
  required String question,
  required List<ChatHistoryTurn> history,
}) {
  final q = question.trim();
  if (history.isEmpty) return q;
  final buffer = StringBuffer()..writeln('سياق المحادثة السابقة:');
  for (final turn in history) {
    buffer.writeln('- سؤال سابق: ${turn.question}');
    buffer.writeln('  إجابة سابقة: ${turn.answer}');
  }
  buffer
    ..writeln()
    ..writeln('السؤال الحالي: $q');
  return buffer.toString();
}

/// تبادل سابق واحد في ذاكرة سياق المحادثة (للموجه فقط).
class ChatHistoryTurn {
  final String question;
  final String answer;
  const ChatHistoryTurn({required this.question, required this.answer});
}

/// قرار الرفض قبل التوليد: يعيد جملة الرفض حرفياً عندما تكون نتيجة
/// الاسترجاع مرفوضة، وnull عندما يُسمح بالتوليد. يستدعيه المزود
/// قبل بناء أي موجه وقبل أي استدعاء للنموذج.
String? ragRefusal(RetrievalResult result) =>
    result.refused ? refusalText : null;
