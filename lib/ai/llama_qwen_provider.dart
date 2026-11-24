// مزود النموذج المحلي: Qwen2.5-Instruct (GGUF) عبر fllama_cpp
// (llama.cpp) — P6.
//
// واجهة fllama المستعملة هنا هي الموثقة فقط في README الرسمي
// (pub.dev — fllama_cpp 1.1.1، وصفحة API في 1.2.0، والتحقق
// 2026-11-25):
//   import 'package:fllama_cpp/fllama_cpp.dart';
//   OpenAiRequest(maxTokens:, messages:, numGpuLayers:, modelPath:,
//                 contextSize:, logger:)
//   Message(Role.system, ...), Message(Role.user, ...)
//   fllamaChat(request, (response, json, done, error) { ... })
// حيث response هو أحدث نص كامل (المثال الرسمي يسند latestResult =
// error?.message ?? response)، وerror غير null فقط عند done مع خطأ.
//
// ما لم يُتحقق منه في تلك المصادر فلا يُستعمل:
// - Role.assistant غير مذكور في المثال الرسمي، لذلك لا تُمرَّر
//   رسائل دور مساعد منفصلة؛ سياق المحادثة يُطوى نصاً موسوماً داخل
//   رسالة المستخدم (انظر prompts.buildUserMessage).
// - لا دالة إيقاف/إلغاء موثقة لـfllamaChat في المصادر المقروءة؛
//   الإلغاء هنا يعني تجاهل الردود المتأخرة بعد dispose فقط، ويُوثَّق
//   ذلك كقيد في PHASE6_TEAM1_NOTES.md.
// - حمولة json في الرد غير مفسَّرة عمداً (استخدامها غير موثق)،
//   لذلك تبقى عدادات الرموز 0 — لا أرقام مخترعة.
//
// مسار التوليد دائماً: استرجاع أولاً (RetrievalService) → إن رُفض
// الاسترجاع يُعاد refusalText حرفياً دون استدعاء النموذج إطلاقاً →
// وإلا يُبنى موجه النظام من المقاطع ويُستدعى النموذج. أي خطأ في
// التحميل أو التوليد يرمي LlamaModelException مكتوباً (لا إجابة
// وهمية) فيلتقطه المساعد ويعود إلى الوضع الاسترجاعي.

import 'dart:async';

import 'package:fllama_cpp/fllama_cpp.dart';

import 'llm_provider.dart';
import 'model_catalog.dart';
import 'model_manager.dart';
import 'prompts.dart';
import 'retrieval_service.dart';

/// خطأ تحميل/توليد في النموذج المحلي برسالة عربية صالحة للعرض.
class LlamaModelException implements Exception {
  final String message;
  const LlamaModelException(this.message);
  @override
  String toString() => message;
}

/// دالة تشغيل محادثة fllama القابلة للحقن (للاختبار والتبديل).
/// توقيع الرد مطابق للمثال الرسمي: (response, json, done, error).
/// الأنواع dynamic عمداً: الأنواع الدقيقة لمعاملات رد fllamaChat
/// غير منشورة في README، وdynamic يقبلها بالتباين العكسي عند
/// التمرير إلى fllamaChat.
typedef LlamaChatRunner = void Function(
  OpenAiRequest request,
  void Function(String response, dynamic json, bool done, dynamic error)
      onEvent,
);

void _defaultRunner(
  OpenAiRequest request,
  void Function(String response, dynamic json, bool done, dynamic error)
      onEvent,
) {
  fllamaChat(request, onEvent);
}

/// مزود التوليد المحلي المقيد بالاسترجاع (RAG) فوق Qwen GGUF.
class LlamaQwenProvider implements LlmProvider {
  final RetrievalService _service;
  final ModelManager _manager;
  final LocalModelSpec spec;
  final LlamaChatRunner _chatRunner;

  bool _disposed = false;

  LlamaQwenProvider({
    RetrievalService? service,
    ModelManager? manager,
    this.spec = qwen3bSpec,
    LlamaChatRunner? chatRunner,
  })  : _service = service ?? RetrievalService(),
        _manager = manager ?? ModelManager(),
        _chatRunner = chatRunner ?? _defaultRunner;

  @override
  String get id => spec.providerId;

  @override
  String get displayName => 'توليد محلي — ${spec.displayNameAr}';

  @override
  bool get isLocal => true;

  @override
  Future<bool> get isReady => _manager.isDownloaded(spec);

  /// مسار ملف النموذج (يُحمَّل عند أول توليد ناجح فقط).
  Future<String> get modelPath async =>
      (await _manager.modelFile(spec)).path;

  @override
  Future<GenerationResult> generate(GenerationRequest req) async {
    final stopwatch = Stopwatch()..start();
    // 1) استرجاع أولاً — والرفض يعيد الجملة حرفياً دون لمس النموذج.
    final result = await _service.retrieve(req.userPrompt, limit: maxRagChunks);
    final refusal = ragRefusal(result);
    if (refusal != null) {
      stopwatch.stop();
      return GenerationResult(
        text: refusal,
        citations: const [],
        refused: true,
        latency: stopwatch.elapsed,
      );
    }
    // 2) موجه النظام من المقاطع المسترجعة فقط.
    final chunks = result.chunks;
    final systemPrompt = buildSystemPrompt(
      style: req.style,
      length: req.length,
      chunks: chunks,
    );
    final userMessage = buildUserMessage(
      question: req.userPrompt,
      history: _historyTurns(req.history),
    );
    // 3) استدعاء النموذج المحلي.
    final path = await modelPath;
    final request = OpenAiRequest(
      maxTokens: req.maxTokens,
      messages: [
        Message(Role.system, systemPrompt),
        Message(Role.user, userMessage),
      ],
      // ‎-1: يلائم llama.cpp الطبقات مع ذاكرة GPU الحرة (المثال الرسمي).
      numGpuLayers: -1,
      modelPath: path,
      contextSize: spec.contextSize,
    );
    final text = await _runChat(request);
    stopwatch.stop();
    final citations = chunks.map(Citation.fromChunk).toList();
    final buffer = StringBuffer()..write(text.trim());
    buffer
      ..writeln()
      ..writeln();
    for (final c in citations) {
      buffer.writeln('• ${c.citationLine}');
    }
    buffer.writeln(generatedAnswerTag);
    return GenerationResult(
      text: buffer.toString().trim(),
      citations: citations,
      refused: false,
      latency: stopwatch.elapsed,
    );
  }

  @override
  Stream<String> generateStream(GenerationRequest req) async* {
    // يبث الزيادات من رد fllama التراكمي؛ وعند الرفض يبث جملة
    // الرفض حرفياً دون استدعاء النموذج.
    final stopwatch = Stopwatch()..start();
    final result = await _service.retrieve(req.userPrompt, limit: maxRagChunks);
    final refusal = ragRefusal(result);
    if (refusal != null) {
      stopwatch.stop();
      yield refusal;
      return;
    }
    final chunks = result.chunks;
    final request = OpenAiRequest(
      maxTokens: req.maxTokens,
      messages: [
        Message(
          Role.system,
          buildSystemPrompt(
              style: req.style, length: req.length, chunks: chunks),
        ),
        Message(
          Role.user,
          buildUserMessage(
            question: req.userPrompt,
            history: _historyTurns(req.history),
          ),
        ),
      ],
      numGpuLayers: -1,
      modelPath: await modelPath,
      contextSize: spec.contextSize,
    );
    final controller = StreamController<String>();
    var lastYielded = '';
    var completed = false;
    // رد fllama تراكمي (المثال الرسمي يسند النص الكامل في كل مرة)،
    // لذلك نُصدر الزيادة فقط؛ وإن وصل نص لا يبدأ بالسابق نُصدره
    // كاملاً ونزامن المؤشر.
    void emitDelta(String response) {
      if (response.length > lastYielded.length &&
          response.startsWith(lastYielded)) {
        final delta = response.substring(lastYielded.length);
        lastYielded = response;
        controller.add(delta);
      } else if (response != lastYielded) {
        lastYielded = response;
        controller.add(response);
      }
    }

    _chatRunner(request, (response, json, done, error) {
      if (_disposed || completed) return;
      if (done && error != null) {
        completed = true;
        controller.addError(
          LlamaModelException(_errorMessage(error)),
        );
        controller.close();
        return;
      }
      if (done) {
        completed = true;
        emitDelta(response);
        controller.close();
        return;
      }
      emitDelta(response);
    });
    yield* controller.stream;
  }

  /// يشغّل محادثة واحدة ويعيد النص الكامل، أو يرمي
  /// [LlamaModelException] عند الخطأ.
  Future<String> _runChat(OpenAiRequest request) {
    final completer = Completer<String>();
    var latest = '';
    _chatRunner(request, (response, json, done, error) {
      if (_disposed) {
        if (!completer.isCompleted) {
          completer.completeError(
            const LlamaModelException('أُلغي التوليد.'),
          );
        }
        return;
      }
      latest = response;
      if (done) {
        if (error != null) {
          if (!completer.isCompleted) {
            completer.completeError(
              LlamaModelException(_errorMessage(error)),
            );
          }
        } else if (!completer.isCompleted) {
          completer.complete(latest);
        }
      }
    });
    return completer.future;
  }

  static String _errorMessage(dynamic error) {
    try {
      final message = error?.message as Object?;
      if (message != null && message.toString().isNotEmpty) {
        return 'تعذّر التوليد المحلي: ${message.toString()}';
      }
    } catch (_) {
      // تجاهل: نعود إلى الرسالة العامة أدناه.
    }
    return 'تعذّر التوليد المحلي (خطأ في تحميل النموذج أو تشغيله). '
        'سيعود المساعد إلى الوضع الاسترجاعي.';
  }

  /// يحوّل ذاكرة المحادثة إلى تبادلات سؤال/إجابة للموجه.
  /// آخر 3 تبادلات فقط (سؤال مستخدم + إجابة مساعد لكل تبادل).
  static List<ChatHistoryTurn> _historyTurns(List<ChatMessage> history) {
    final turns = <ChatHistoryTurn>[];
    String? pendingQuestion;
    for (final m in history) {
      if (m.role == 'user') {
        pendingQuestion = m.text;
      } else if (m.role == 'assistant' && pendingQuestion != null) {
        turns.add(
          ChatHistoryTurn(question: pendingQuestion, answer: m.text),
        );
        pendingQuestion = null;
      }
    }
    if (turns.length > 3) return turns.sublist(turns.length - 3);
    return turns;
  }

  @override
  Future<void> dispose() async {
    // لا دالة إيقاف موثقة لـfllamaChat؛ نكتفي بتجاهل الردود المتأخرة.
    _disposed = true;
  }
}
