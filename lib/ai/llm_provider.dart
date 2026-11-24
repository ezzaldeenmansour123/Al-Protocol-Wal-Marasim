// واجهة المزود القابلة للتبديل (V2_PLAN §2.3) + التنفيذان المتاحان:
// RetrievalOnlyProvider (id='retrieval-only') وLlamaQwenProvider
// (P6 — lib/ai/llama_qwen_provider.dart: Qwen GGUF عبر fllama_cpp).
//
// لا تنفيذ سحابي هنا، ولا كود شبكة لخدمة ذكاء اصطناعي، ولا مفاتيح:
// المزود الاسترجاعي يعيد المقاطع المسترجعة حرفياً موسومة
// «من قاعدة المعرفة — بلا توليد»، وعند الرفض يعيد جملة الرفض حرفياً؛
// ومزود النموذج المحلي يولّد مقيداً بالمقاطع المسترجعة فقط، وعند
// غياب النموذج أو فشل تحميله يعود المساعد تلقائياً إلى الاسترجاعي.

import 'answer_style.dart';
import 'retrieval_core.dart';
import 'retrieval_service.dart';

export 'answer_style.dart';

/// رسالة واحدة في ذاكرة سياق المحادثة.
class ChatMessage {
  /// 'user' أو 'assistant'.
  final String role;
  final String text;
  const ChatMessage({required this.role, required this.text});
}

/// استشهاد واحد: موضوع + صفحة كتاب + نوع المصدر.
class Citation {
  final String topicId;
  final String title;
  final int? bookPageStart;
  final int? bookPageEnd;
  final String sourceType;
  final String source;
  const Citation({
    required this.topicId,
    required this.title,
    this.bookPageStart,
    this.bookPageEnd,
    required this.sourceType,
    required this.source,
  });

  factory Citation.fromChunk(RetrievedChunk c) => Citation(
        topicId: c.topicId,
        title: c.title,
        bookPageStart: c.bookPageStart,
        bookPageEnd: c.bookPageEnd,
        sourceType: c.sourceType,
        source: c.source,
      );

  String get citationLine {
    if (bookPageStart != null && bookPageEnd != null) {
      return 'المصدر: $source — ص. $bookPageStart–$bookPageEnd';
    }
    return 'المصدر: $source';
  }
}

/// طلب توليد واحد (يُستخدم كما هو من أي مزود مستقبلي).
class GenerationRequest {
  /// تعليمة النظام (الأسلوب + قواعد عدم الاختلاق).
  final String systemPrompt;

  /// آخر تبادلات المحادثة (ذاكرة سياق).
  final List<ChatMessage> history;

  /// سؤال المستخدم.
  final String userPrompt;

  /// مقاطع RAG الممررة إلى النموذج (إن وُجدت مسبقاً).
  final List<RetrievedChunk> context;

  final AnswerStyle style;
  final AnswerLength length;
  final int maxTokens;

  const GenerationRequest({
    this.systemPrompt = '',
    this.history = const [],
    required this.userPrompt,
    this.context = const [],
    this.style = AnswerStyle.diplomatic,
    this.length = AnswerLength.medium,
    this.maxTokens = 1024,
  });
}

/// نتيجة توليد واحدة.
class GenerationResult {
  final String text;
  final List<Citation> citations;

  /// true إن كان الرد جملة الرفض.
  final bool refused;
  final int promptTokens;
  final int outputTokens;
  final Duration latency;

  const GenerationResult({
    required this.text,
    required this.citations,
    required this.refused,
    this.promptTokens = 0,
    this.outputTokens = 0,
    this.latency = Duration.zero,
  });
}

/// واجهة المزود الواحدة (V2_PLAN §2.3).
/// قواعدها: لا يستورد أي مزود واجهةَ مستخدم؛ وكل مزود يفشل بخطأ
/// مكتوب لا بإجابة وهمية.
abstract class LlmProvider {
  /// مثل 'llama-qwen3b' | 'retrieval-only'.
  String get id;
  String get displayName;

  /// true لكل مزود محلي؛ false للسحابي (المستقبلي).
  bool get isLocal;

  /// النموذج منزَّل ومُحمَّل أم لا (للاسترجاعي: قاعدة المعرفة موجودة).
  Future<bool> get isReady;

  Future<GenerationResult> generate(GenerationRequest req);

  /// بثّ رمزي مع إلغاء؛ الافتراضي يعيد نتيجة generate دفعة واحدة.
  Stream<String> generateStream(GenerationRequest req) async* {
    yield (await generate(req)).text;
  }

  Future<void> dispose();
}

/// المزود النظامي الدائم: استرجاع فقط، بلا توليد.
/// يُستخدم عند غياب النموذج أو فشله أو رفض الجهاز له — فالمساعد لا
/// يكون «معطلاً» أبداً، بل «استرجاعياً» ويُقال ذلك.
class RetrievalOnlyProvider implements LlmProvider {
  final RetrievalService _service;

  RetrievalOnlyProvider({RetrievalService? service})
      : _service = service ?? RetrievalService();

  @override
  String get id => 'retrieval-only';

  @override
  String get displayName => 'وضع استرجاعي (بلا توليد)';

  @override
  bool get isLocal => true;

  @override
  Future<bool> get isReady => _service.isReady;

  @override
  Future<GenerationResult> generate(GenerationRequest req) async {
    final stopwatch = Stopwatch()..start();
    // يسترجع دائماً من قاعدة البيانات المحلية لحظة الطلب، حتى لا
    // تُعرض استشهادات قديمة من سياق سابق.
    final result = await _service.retrieve(req.userPrompt);
    stopwatch.stop();
    if (result.refused) {
      return GenerationResult(
        text: refusalText,
        citations: const [],
        refused: true,
        latency: stopwatch.elapsed,
      );
    }
    final buffer = StringBuffer()..writeln(retrievalOnlyTag);
    for (final chunk in result.chunks) {
      buffer
        ..writeln()
        ..writeln('• ${chunk.title}')
        ..writeln(chunk.excerpt)
        ..writeln(chunk.citationLine);
      if (chunk.textStatus.isNotEmpty) {
        buffer.writeln('حالة النص: ${chunk.textStatus}');
      }
    }
    return GenerationResult(
      text: buffer.toString().trim(),
      citations: result.chunks.map(Citation.fromChunk).toList(),
      refused: false,
      latency: stopwatch.elapsed,
    );
  }

  @override
  Stream<String> generateStream(GenerationRequest req) async* {
    yield (await generate(req)).text;
  }

  @override
  Future<void> dispose() async {}
}
