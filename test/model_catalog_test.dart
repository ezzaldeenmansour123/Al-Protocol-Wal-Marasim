// اختبار كتالوج النماذج المحلية (lib/ai/model_catalog.dart).
//
// سكربت Dart مستقل: main() مع asserts فقط، بلا flutter_test، حتى
// يُشغَّل مباشرة بـ `dart`:
//   dart test/model_catalog_test.dart
// (يُشغَّل أيضاً من CI عبر الغلاف test/model_catalog_flutter_test.dart).
// يغطي: مواصفات النموذجين (المستودع والملف والحجم كما في Hugging
// Face)، روابط التنزيل، تنسيق الأحجام، وحساب المساحة المطلوبة.
// لا شبكة: الروابط تُبنى وتُقارن نصاً فقط — لا يُنزَّل أي ملف.

import '../lib/ai/model_catalog.dart';

int _passed = 0;

void check(bool ok, String name) {
  assert(ok, name);
  if (!ok) throw StateError('FAIL: $name');
  _passed++;
  print('  PASS: $name');
}

void main() {
  print('model_catalog_test — pure Dart, no flutter_test');

  // ── 1. النموذج الأساسي 3B ──
  print('1) qwen3bSpec');
  check(qwen3bSpec.repoId == 'bartowski/Qwen2.5-3B-Instruct-GGUF',
      'M01: مستودع 3B');
  check(qwen3bSpec.filename == 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      'M02: ملف 3B Q4_K_M');
  check(qwen3bSpec.approxBytes == 1930000000, 'M03: حجم 3B التقريبي 1.93GB');
  check(qwen3bSpec.providerId == 'llama-qwen3b', 'M04: معرّف مزود 3B');
  check(qwen3bSpec.minRamBytes == 4 * 1024 * 1024 * 1024,
      'M05: ذاكرة 3B الموصى بها 4GB');

  // ── 2. البديل الأخف 1.5B ──
  print('2) qwen15bSpec');
  check(qwen15bSpec.repoId == 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      'M06: مستودع 1.5B');
  check(qwen15bSpec.filename == 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      'M07: ملف 1.5B Q4_K_M');
  check(qwen15bSpec.approxBytes == 990000000, 'M08: حجم 1.5B التقريبي 0.99GB');
  check(qwen15bSpec.providerId == 'llama-qwen15b', 'M09: معرّف مزود 1.5B');
  check(qwen15bSpec.approxBytes < qwen3bSpec.approxBytes,
      'M10: البديل أصغر من الأساسي');
  check(defaultLocalModelSpec.id == LocalModelId.qwen3b,
      'M11: الافتراضي هو 3B');

  // ── 3. روابط Hugging Face ──
  print('3) download URLs');
  check(
      huggingFaceDownloadUrl(qwen3bSpec) ==
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      'M12: رابط تنزيل 3B');
  check(
      huggingFaceDownloadUrl(qwen15bSpec) ==
          'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      'M13: رابط تنزيل 1.5B');
  check(huggingFaceApiUrl(qwen3bSpec) ==
          'https://huggingface.co/api/models/bartowski/Qwen2.5-3B-Instruct-GGUF',
      'M14: رابط API للـSHA-256');
  check(!huggingFaceDownloadUrl(qwen3bSpec).contains(' '),
      'M15: الرابط بلا مسافات');

  // ── 4. البحث بالمعرف ──
  print('4) spec lookup');
  check(specForId(LocalModelId.qwen15b) == qwen15bSpec, 'M16: بحث بالمعرف');
  check(specForProviderId('llama-qwen3b') == qwen3bSpec,
      'M17: بحث بمعرف المزود');
  check(specForProviderId('unknown') == null, 'M18: معرّف مجهول يعيد null');

  // ── 5. تنسيق الأحجام (عشري ليطابق Hugging Face) ──
  print('5) formatBytes');
  check(formatBytes(1930000000) == '1.93 GB', 'M19: 1.93 GB للملف 3B');
  check(formatBytes(990000000) == '990 MB', 'M20: 990 MB للملف 1.5B');
  check(formatBytes(512 * 1024 * 1024) == '537 MB',
      'M21: هامش 512MiB بالوحدات العشرية');
  check(formatBytes(500) == '500 B', 'M22: بايتات صغيرة');

  // ── 6. المساحة المطلوبة ──
  print('6) space requirements');
  check(remainingBytes(qwen3bSpec, 0) == 1930000000, 'M23: المتبقي كاملاً');
  check(remainingBytes(qwen3bSpec, 1930000000) == 0, 'M24: المتبقي صفر');
  check(remainingBytes(qwen3bSpec, 9999999999) == 0,
      'M25: المتبقي لا يسلب أبداً');
  check(hasEnoughFreeSpace(qwen3bSpec, 3000000000),
      'M26: 3GB حرة تكفي 3B + الهامش');
  check(!hasEnoughFreeSpace(qwen3bSpec, 2000000000),
      'M27: 2GB حرة لا تكفي 3B + الهامش');
  check(hasEnoughFreeSpace(qwen3bSpec, 1000000000,
          alreadyDownloadedBytes: 1500000000),
      'M28: الاستئناف يخصم ما نُزّل');

  print('ALL PASSED ($_passed checks)');
}
