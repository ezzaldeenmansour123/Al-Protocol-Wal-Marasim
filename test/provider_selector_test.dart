// اختبار منطق اختيار المزود (lib/ai/provider_selector.dart).
//
// سكربت Dart مستقل: main() مع asserts فقط، بلا flutter_test، حتى
// يُشغَّل مباشرة بـ `dart`:
//   dart test/provider_selector_test.dart
// (يُشغَّل أيضاً من CI عبر الغلاف test/provider_selector_flutter_test.dart).
// يغطي مصفوفة القرار كاملة: النموذج المحلي يعمل فقط عند جاهزيته،
// وفي كل حالة أخرى يعود المساعد إلى الوضع الاسترجاعي مع وسم صادق.
// لا قاعدة بيانات ولا شبكة ولا نموذج.

import '../lib/ai/model_catalog.dart';
import '../lib/ai/provider_selector.dart';

int _passed = 0;

void check(bool ok, String name) {
  assert(ok, name);
  if (!ok) throw StateError('FAIL: $name');
  _passed++;
  print('  PASS: $name');
}

ProviderDecision decide({
  bool selected = true,
  bool downloaded = true,
  bool valid = true,
  bool loadOk = true,
}) =>
    resolveProvider(
      spec: qwen3bSpec,
      modelSelected: selected,
      modelDownloaded: downloaded,
      modelFileValid: valid,
      lastLoadOk: loadOk,
    );

void main() {
  print('provider_selector_test — pure Dart, no flutter_test');

  // ── 1. مصفوفة القرار ──
  print('1) decision matrix');
  final ready = decide();
  check(ready.choice == ProviderChoice.localModel, 'S01: جاهز → محلي');
  check(ready.reason == 'model_ready', 'S02: سبب الجاهزية');
  check(ready.spec == qwen3bSpec, 'S03: القرار يحمل المواصفات');
  check(decide(selected: false).choice == ProviderChoice.retrievalOnly,
      'S04: غير مفعّل → استرجاعي');
  check(decide(selected: false).reason == 'model_not_selected',
      'S05: سبب عدم التفعيل');
  check(decide(downloaded: false).reason == 'no_model',
      'S06: غير منزّل → no_model');
  check(decide(downloaded: false).choice == ProviderChoice.retrievalOnly,
      'S07: غير منزّل → استرجاعي');
  check(decide(valid: false).reason == 'model_invalid',
      'S08: ملف غير سليم → model_invalid');
  check(decide(loadOk: false).reason == 'model_load_failed',
      'S09: فشل تحميل سابق → model_load_failed');
  check(decide(loadOk: false).choice == ProviderChoice.retrievalOnly,
      'S10: فشل تحميل سابق → استرجاعي رغم وجود الملف');
  check(decide(selected: false, downloaded: false, valid: false,
          loadOk: false)
      .reason == 'model_not_selected',
      'S11: عدم التفعيل يتقدم على باقي الأسباب');
  check(decide(downloaded: false, valid: false).reason == 'no_model',
      'S12: غياب الملف يتقدم على عدم السلامة');

  // ── 2. الوسم الصادق ──
  print('2) providerModeTag');
  check(providerModeTag(ready).contains('توليد محلي'),
      'S13: وسم المحلي يصرّح بالتوليد');
  check(providerModeTag(ready).contains('Qwen2.5-3B'),
      'S14: وسم المحلي يسمّي النموذج');
  check(providerModeTag(ready).contains('مقيّد بمقاطع'),
      'S15: وسم المحلي يصرّح بالتقييد بالمقاطع');
  for (final d in [
    decide(selected: false),
    decide(downloaded: false),
    decide(valid: false),
    decide(loadOk: false),
  ]) {
    final tag = providerModeTag(d);
    check(tag.contains('وضع استرجاعي'),
        'S16: وسم السقوط يصرّح بالوضع الاسترجاعي (${d.reason})');
    check(!tag.contains('توليد محلي'),
        'S17: وسم السقوط لا يدّعي التوليد (${d.reason})');
  }
  check(providerModeTag(decide(downloaded: false)).contains('لم يُنزَّل بعد'),
      'S18: وسم غياب النموذج يذكر السبب');
  check(providerModeTag(decide(valid: false)).contains('غير سليم'),
      'S19: وسم الملف التالف يذكر السبب');
  check(providerModeTag(decide(loadOk: false)).contains('تعذّر تحميل'),
      'S20: وسم فشل التحميل يذكر السبب');

  print('ALL PASSED ($_passed checks)');
}
