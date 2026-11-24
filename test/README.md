# اختبارات طبقة الاسترجاع (RAG الاسترجاعي — المرحلة الثانية)

## الملفات

| الملف | الوصف |
|---|---|
| `retrieval_core_test.dart` | سكربت Dart مستقل: `main()` مع asserts فقط، **بلا `flutter_test`**، يغطي التطبيع العربي، إزالة كلمات التوقف، تعبيرات FTS5، قرار الرفض (صفر نتائج / نتائج ضعيفة)، وبناء `RetrievedChunk` مع رقم صفحة الكتاب، **+ أقسام R1**: ترجيح العنوان (`countTitleMatchedTerms`، جلب 20 مرشحاً)، كلمات التوقف الإنجليزية، والتجريد الصرفي (بادئة واحدة ولواحق ضمائر/مثنى). |
| `retrieval_core_flutter_test.dart` | غلاف `flutter_test` يستدعي `main()` من السكربت أعلاه داخل `test()` حقيقي، حتى تُبلَّغ نتيجته في CI. |
| `refusal_guard_test.dart` | سكربت Dart مستقل (R1): `main()` مع asserts فقط، **بلا `flutter_test`**، يغطي حارس منع الاختلاق `lib/ai/refusal_guard.dart` — قاعدة نطاق مواد فيينا (1–53) عربياً وإنجليزياً وبالأرقام المشرقية، عتبة الصلة (مصطلحان مميزان)، ونص الرفض الحرفي، وحدوده الموثقة (لا يكشف الدول/الألقاب المخترعة). |
| `refusal_guard_flutter_test.dart` | غلاف `flutter_test` يستدعي `main()` من سكربت الحارس داخل `test()` حقيقي، حتى تُبلَّغ نتيجته في CI. |
| `prompts_test.dart` | سكربت Dart مستقل (P6): `main()` مع asserts فقط، **بلا `flutter_test`**، يغطي موجهات التوليد المقيّد بالاسترجاع `lib/ai/prompts.dart` — كتلة السياق (عنوان + مقتطف + صفحة كتاب)، موجهات النظام للأساليب السبعة والأطوال الثلاثة، القواعد الصارمة (لا إجابة إلا من المقاطع، تمييز معلومات الكتاب عن التحليل)، رسالة المستخدم مع سياق المحادثة، وقرار الرفض قبل التوليد (جملة الرفض حرفياً). |
| `prompts_flutter_test.dart` | غلاف `flutter_test` يستدعي `main()` من سكربت الموجهات داخل `test()` حقيقي، حتى تُبلَّغ نتيجته في CI. |
| `model_catalog_test.dart` | سكربت Dart مستقل (P6): `main()` مع asserts فقط، **بلا `flutter_test`**، يغطي كتالوج النماذج `lib/ai/model_catalog.dart` — مواصفات النموذجين (المستودع والملف والحجم كما في Hugging Face)، روابط التنزيل، تنسيق الأحجام، وحساب المساحة المطلوبة. لا شبكة: الروابط تُقارن نصاً فقط. |
| `model_catalog_flutter_test.dart` | غلاف `flutter_test` يستدعي `main()` من سكربت الكتالوج داخل `test()` حقيقي، حتى تُبلَّغ نتيجته في CI. |
| `provider_selector_test.dart` | سكربت Dart مستقل (P6): `main()` مع asserts فقط، **بلا `flutter_test`**، يغطي منطق اختيار المزود `lib/ai/provider_selector.dart` — مصفوفة القرار كاملة (النموذج المحلي فقط عند جاهزيته، وإلا الاسترجاعي) والوسم الصادق لكل حالة. |
| `provider_selector_flutter_test.dart` | غلاف `flutter_test` يستدعي `main()` من سكربت المحدد داخل `test()` حقيقي، حتى تُبلَّغ نتيجته في CI. |

## التشغيل محلياً (بلا Flutter SDK)

```sh
# من جذر المستودع، بأي Dart SDK (مثلاً ~/workspace/sunnah/.tools/dart-sdk/bin/dart):
dart test/retrieval_core_test.dart
dart test/refusal_guard_test.dart
dart test/prompts_test.dart
dart test/model_catalog_test.dart
dart test/provider_selector_test.dart
```

السكربتات تختبر `lib/ai/retrieval_core.dart` و`lib/ai/refusal_guard.dart`
و`lib/ai/prompts.dart` و`lib/ai/model_catalog.dart`
و`lib/ai/provider_selector.dart` فقط — Pure Dart بلا أي استيراد Flutter — لذلك تعملان بـ`dart` مباشرة.
النجاح يعني سطر `ALL PASSED (60 checks)` للنواة و`ALL PASSED (22 checks)`
للحارس و`ALL PASSED (58 checks)` للموجهات و`ALL PASSED (28 checks)`
للكتالوج و`ALL PASSED (26 checks)` للمحدد وخروج برمز 0؛ أي فشل يرمي `StateError` باسم الفحص الفاشل ويخرج
برمز غير صفري.

## التشغيل في CI (GitHub Actions)

سير العمل `.github/workflows/build.yml` يشغّل بعد خطوة `Analyze`:

```sh
flutter test test/retrieval_core_flutter_test.dart
flutter test test/refusal_guard_flutter_test.dart
```

الملف محدد بالاسم عمداً: السكربت الخالص لا يسجّل حالات `flutter_test`
بنفسه (ليبقى قابلاً للتشغيل بـ`dart`)، والغلاف هو ما يسجّل حالة
اختبار حقيقية. خطوة `flutter create` في CI تحذف فقط
`test/widget_test.dart` (اختبار العدّاد القالبي المولَّد) وتُبقي
مجلد `test/` الخاص بالمستودع — لا تحذف `test/` أبداً.

## ما لا تغطيه هذه الاختبارات

- `lib/ai/retrieval_service.dart` و`lib/ai/llm_provider.dart` و`lib/ai/llama_qwen_provider.dart`
  و`lib/ai/model_manager.dart` و`lib/ai/provider_factory.dart` و`lib/model_settings.dart`
  وترحيل `lib/db.dart` وربط `lib/assistant.dart`: تعتمد `sqflite` وFlutter
  و`fllama_cpp` و`path_provider` فلا تُشغَّل بـ`dart` مباشرة. يُتحقق منها بـ`flutter test` /
  `flutter analyze` في CI وعلى جهاز Android، وبالفحص المتبادل
  لـSQL على قاعدة اختبار SQLite (انظر `docs/RAG_PHASE2.md`).
  منطقها الخالص مغطى بديلاً في `prompts_test.dart` و`model_catalog_test.dart`
  و`provider_selector_test.dart` (بناء الموجهات، قرار الرفض، اختيار المزود).
- جودة ترتيب الاسترجاع نفسها (أي مقطع أولاً لكل سؤال): تُقاس
  بمجموعة الـ100 سؤال (P4)، لا باختبارات الوحدات هذه.
