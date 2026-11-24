// كتالوج النماذج المحلية (P6 — Pure Dart فقط، dart:core).
//
// يصف النموذجين المدعومين وروابط تنزيلهما من Hugging Face. لا شبكة
// هنا: هذا الملف بيانات وحسابات فقط؛ التنزيل الفعلي في
// lib/ai/model_manager.dart.
//
// المصدر (تم التحقق منه 2026-11-25):
// - النموذج الأساسي: bartowski/Qwen2.5-3B-Instruct-GGUF — الملف
//   Qwen2.5-3B-Instruct-Q4_K_M.gguf — 1.93GB كما تعرضه Hugging Face.
// - البديل الأخف: bartowski/Qwen2.5-1.5B-Instruct-GGUF — الملف
//   Qwen2.5-1.5B-Instruct-Q4_K_M.gguf — 0.99GB (986MB) كما تعرضه
//   Hugging Face.
// - النموذج الأصلي في الحالتين Qwen/Qwen2.5-{3B,1.5B}-Instruct من
//   Alibaba Cloud؛ الترخيص Qwen License (راجع صفحة المستودع قبل
//   التوزيع — التطبيق ينزّل الملف على جهاز المستخدم فقط ولا يعيد
//   توزيعه).
//
// الأحجام «تقريبية» عمداً: قد يعيد الناشر نشر الملف فيتغير حجمه.
// مدير التنزيل يقرأ الحجم الفعلي من ترويسة Content-Length عند بدء
// التنزيل ويعتمد عليه، وهذه الأرقام للعرض المسبق قبل التنزيل فقط.

/// معرّف النموذج المحلي.
enum LocalModelId {
  /// Qwen2.5-3B-Instruct Q4_K_M — الأساسي (~1.93GB).
  qwen3b,

  /// Qwen2.5-1.5B-Instruct Q4_K_M — الأخف (~0.99GB).
  qwen15b,
}

/// وصف نموذج محلي واحد قابل للتنزيل.
class LocalModelSpec {
  final LocalModelId id;
  final String repoId;
  final String filename;
  final String displayNameAr;
  final String displayNameEn;

  /// الحجم التقريبي بالبايت كما تعرضه Hugging Face (للعرض المسبق).
  final int approxBytes;

  /// الذاكرة (RAM) الدنيا الموصى بها بالبايت أثناء التشغيل.
  /// قاعدة fllama: «ستحتاج ذاكرة بقدر حجم ملف النموذج تقريباً»؛
  /// نضيف هامش سياق الاستدلال فيُوصى بـ 4GB للنموذج 3B و2GB لـ 1.5B.
  final int minRamBytes;

  /// حجم سياق الاستدلال (رموز) — 4096 قيمة fllama الافتراضية الجيدة.
  final int contextSize;

  const LocalModelSpec({
    required this.id,
    required this.repoId,
    required this.filename,
    required this.displayNameAr,
    required this.displayNameEn,
    required this.approxBytes,
    required this.minRamBytes,
    this.contextSize = 4096,
  });

  /// معرّف المزود المقابل في واجهة LlmProvider.
  String get providerId =>
      id == LocalModelId.qwen3b ? 'llama-qwen3b' : 'llama-qwen15b';

  /// اسم الملف المحلي (اسم ملف GGUF نفسه).
  String get localFilename => filename;
}

/// النموذج الأساسي: Qwen2.5-3B-Instruct Q4_K_M (~1.93GB).
const LocalModelSpec qwen3bSpec = LocalModelSpec(
  id: LocalModelId.qwen3b,
  repoId: 'bartowski/Qwen2.5-3B-Instruct-GGUF',
  filename: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
  displayNameAr: 'Qwen2.5-3B-Instruct ‏(Q4_K_M)‏ — الأساسي',
  displayNameEn: 'Qwen2.5-3B-Instruct (Q4_K_M) — default',
  approxBytes: 1930000000,
  minRamBytes: 4 * 1024 * 1024 * 1024,
);

/// البديل الأخف: Qwen2.5-1.5B-Instruct Q4_K_M (~0.99GB).
const LocalModelSpec qwen15bSpec = LocalModelSpec(
  id: LocalModelId.qwen15b,
  repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
  filename: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
  displayNameAr: 'Qwen2.5-1.5B-Instruct ‏(Q4_K_M)‏ — الأخف',
  displayNameEn: 'Qwen2.5-1.5B-Instruct (Q4_K_M) — light',
  approxBytes: 990000000,
  minRamBytes: 2 * 1024 * 1024 * 1024,
);

/// كل النماذج المدعومة بالترتيب المعروض (الأساسي أولاً).
const List<LocalModelSpec> localModelSpecs = [qwen3bSpec, qwen15bSpec];

/// النموذج الافتراضي عند أول إعداد.
const LocalModelSpec defaultLocalModelSpec = qwen3bSpec;

/// يعيد مواصفات النموذج من معرّفه، أو null إن لم يُعرف.
LocalModelSpec? specForId(LocalModelId id) {
  for (final s in localModelSpecs) {
    if (s.id == id) return s;
  }
  return null;
}

/// يعيد مواصفات النموذج من معرّف المزود ('llama-qwen3b' …)، أو null.
LocalModelSpec? specForProviderId(String providerId) {
  for (final s in localModelSpecs) {
    if (s.providerId == providerId) return s;
  }
  return null;
}

/// رابط تنزيل الملف من Hugging Face — نفس بناء getHuggingFaceUrl في
/// توثيق fllama_cpp (pub.dev): {endpoint}/{repoId}/resolve/{revision}/
/// {filename}. بلا مفتاح وبلا حساب: المستودعان عامّان.
String huggingFaceDownloadUrl(LocalModelSpec spec, {String revision = 'main'}) {
  final encodedRevision = Uri.encodeComponent(revision);
  final encodedFilename = Uri.encodeComponent(spec.filename);
  return 'https://huggingface.co/${spec.repoId}/resolve/$encodedRevision/$encodedFilename';
}

/// رابط واجهة Hugging Face API لبيانات المستودع — يُستخدم في
/// ModelManager لقراءة SHA-256 المتوقع من بيانات LFS للملف
/// (siblings[].lfs.oid) عند توفره؛ غيابه لا يمنع التنزيل، بل يُوثَّق
/// ويُكتفى حينها بالتحقق من حجم الملف.
String huggingFaceApiUrl(LocalModelSpec spec) =>
    'https://huggingface.co/api/models/${spec.repoId}';

/// هامش مساحة حرة إضافي مطلوب فوق حجم الملف أثناء التنزيل
/// (ملف .part + إعادة التسمية): 512MB.
const int downloadFreeSpaceMarginBytes = 512 * 1024 * 1024;

/// البايتات التي ما زال تنزيلها مطلوباً (الحجم التقريبي ناقص ما نُزّل).
int remainingBytes(LocalModelSpec spec, int alreadyDownloadedBytes) {
  final r = spec.approxBytes - alreadyDownloadedBytes;
  return r < 0 ? 0 : r;
}

/// هل تكفي المساحة الحرة المعلنة لتنزيل النموذج (مع الهامش)؟
/// ملاحظة صريحة: Dart/Flutter لا يوفران API محمولاً لقراءة المساحة
/// الحرة على Android، لذلك لا يفحص التطبيق قرص الجهاز بنفسه؛ هذه
/// الدالة تحسب الشرط فقط عندما يزوّدها المتصل برقم مساحة حرة من
/// مصدر خارجي، والواجهة تعرض الحجم المطلوب للمستخدم ليتحقق بنفسه.
bool hasEnoughFreeSpace(
  LocalModelSpec spec,
  int freeBytes, {
  int alreadyDownloadedBytes = 0,
}) =>
    freeBytes >=
    remainingBytes(spec, alreadyDownloadedBytes) +
        downloadFreeSpaceMarginBytes;

/// تنسيق حجم بالبايت للعرض («1.93 GB»، «990 MB»).
/// وحدات عشرية (1000) عمداً لتطابق ما تعرضه Hugging Face في قوائم
/// الملفات (1.93 GB للملف 3B، 0.99 GB للملف 1.5B).
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value >= 10
          ? value.toStringAsFixed(1)
          : value.toStringAsFixed(2);
  return '$text ${units[unit]}';
}
