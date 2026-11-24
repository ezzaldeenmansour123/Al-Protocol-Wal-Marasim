// مصنع مزود المساعد (P6): يختار النموذج المحلي عند جاهزيته،
// وإلا الوضع الاسترجاعي — بلا استثناء وبلا وسم كاذب.
//
// يستدعيه AssistantPage عند الإقلاع وعند تغيّر إعدادات النموذج.
// [lastLoadOk=false] بعد فشل تحميل سابق يجبر العودة إلى الوضع
// الاسترجاعي حتى لو كان الملف موجوداً (يُعاد التحميل من الإعدادات).

import 'llama_qwen_provider.dart';
import 'llm_provider.dart';
import 'model_manager.dart';
import 'provider_selector.dart';
import 'retrieval_service.dart';

/// يحلّ مزود المساعد الحالي + قرار الاختيار (لوسم الواجهة).
/// لا يرمي أبداً: عند أي خطأ في فحص النموذج يعود إلى الاسترجاعي.
Future<({LlmProvider provider, ProviderDecision decision})>
    resolveAssistantProvider({
  ModelManager? manager,
  RetrievalService? service,
  bool lastLoadOk = true,
}) async {
  final m = manager ?? ModelManager();
  try {
    final spec = await m.selectedModel();
    final selected = await m.isModelSelected();
    final downloaded = await m.isDownloaded(spec);
    final valid = downloaded
        ? await m.verifyFile(spec)
        : false;
    final decision = resolveProvider(
      spec: spec,
      modelSelected: selected,
      modelDownloaded: downloaded,
      modelFileValid: valid,
      lastLoadOk: lastLoadOk,
    );
    if (decision.choice == ProviderChoice.localModel) {
      return (
        provider: LlamaQwenProvider(
          service: service,
          manager: m,
          spec: spec,
        ),
        decision: decision,
      );
    }
    return (
      provider: RetrievalOnlyProvider(service: service),
      decision: decision,
    );
  } catch (_) {
    return (
      provider: RetrievalOnlyProvider(service: service),
      decision: const ProviderDecision(
        choice: ProviderChoice.retrievalOnly,
        reason: 'model_load_failed',
      ),
    );
  }
}

/// الوسم الصادق المعروض في واجهة المساعد عن وضع التشغيل الحالي.
String assistantModeTag(ProviderDecision decision) =>
    providerModeTag(decision);
