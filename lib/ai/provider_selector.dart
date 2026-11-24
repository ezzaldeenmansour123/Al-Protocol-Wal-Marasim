// منطق اختيار المزود (P6 — Pure Dart فقط، dart:core).
//
// قرار خالص بلا Flutter ولا قرص ولا شبكة: أي مزود يعمل به المساعد؟
// النموذج المحلي يعمل فقط عندما يكون منزّلاً وسليماً ولم يفشل آخر
// تحميل له؛ في كل حالة أخرى يعود المساعد تلقائياً إلى الوضع
// الاسترجاعي مع وسم صادق — المساعد لا يكون «معطلاً» أبداً.

import 'model_catalog.dart';

/// أي مزود يعمل به المساعد.
enum ProviderChoice {
  /// النموذج المحلي (llama.cpp + Qwen GGUF).
  localModel,

  /// الوضع الاسترجاعي (RetrievalOnlyProvider) — بلا توليد.
  retrievalOnly,
}

/// نتيجة قرار الاختيار: المزود + سبب القرار (للسجلات والوسم).
class ProviderDecision {
  final ProviderChoice choice;

  /// أحد الأسباب: 'model_ready'، 'no_model'، 'model_invalid'،
  /// 'model_load_failed'، 'model_not_selected'.
  final String reason;

  /// مواصفات النموذج المختار عند اختيار النموذج المحلي.
  final LocalModelSpec? spec;

  const ProviderDecision({
    required this.choice,
    required this.reason,
    this.spec,
  });
}

/// يقرر المزود من حالة النموذج:
/// - [modelSelected]: هل اختار المستخدم النموذج المحلي في الإعدادات.
/// - [modelDownloaded]: هل ملف GGUF موجود ومكتمل على الجهاز.
/// - [modelFileValid]: هل اجتاز الملف التحقق (الحجم، وSHA-256 عند توفره).
/// - [lastLoadOk]: هل نجح آخر تحميل للنموذج (false بعد فشل تحميل).
ProviderDecision resolveProvider({
  required LocalModelSpec spec,
  required bool modelSelected,
  required bool modelDownloaded,
  required bool modelFileValid,
  required bool lastLoadOk,
}) {
  if (!modelSelected) {
    return const ProviderDecision(
      choice: ProviderChoice.retrievalOnly,
      reason: 'model_not_selected',
    );
  }
  if (!modelDownloaded) {
    return const ProviderDecision(
      choice: ProviderChoice.retrievalOnly,
      reason: 'no_model',
    );
  }
  if (!modelFileValid) {
    return const ProviderDecision(
      choice: ProviderChoice.retrievalOnly,
      reason: 'model_invalid',
    );
  }
  if (!lastLoadOk) {
    return const ProviderDecision(
      choice: ProviderChoice.retrievalOnly,
      reason: 'model_load_failed',
    );
  }
  return ProviderDecision(
    choice: ProviderChoice.localModel,
    reason: 'model_ready',
    spec: spec,
  );
}

/// الوسم الصادق المعروض في واجهة المساعد عن وضع التشغيل الحالي.
String providerModeTag(ProviderDecision decision) {
  switch (decision.choice) {
    case ProviderChoice.localModel:
      final name = decision.spec?.displayNameAr ?? 'النموذج المحلي';
      return 'توليد محلي: $name — مقيّد بمقاطع قاعدة المعرفة';
    case ProviderChoice.retrievalOnly:
      switch (decision.reason) {
        case 'no_model':
          return 'وضع استرجاعي: يبحث في قاعدة المعرفة فقط — النموذج المحلي لم يُنزَّل بعد (الإعدادات ← النموذج المحلي)';
        case 'model_invalid':
          return 'وضع استرجاعي: يبحث في قاعدة المعرفة فقط — ملف النموذج غير سليم، أعد تنزيله من الإعدادات';
        case 'model_load_failed':
          return 'وضع استرجاعي: يبحث في قاعدة المعرفة فقط — تعذّر تحميل النموذج المحلي';
        case 'model_not_selected':
          return 'وضع استرجاعي: يبحث في قاعدة المعرفة فقط — التوليد المحلي غير مفعّل';
        default:
          return 'وضع استرجاعي: يبحث في قاعدة المعرفة فقط — بلا توليد';
      }
  }
}
