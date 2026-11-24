# دليل تشغيل CI — PROTOCOL & CEREMONIAL

- **التاريخ:** 2026-11-25 (المرحلة P6 — فريق الجاهزية)
- **المستودع:** https://github.com/ezzaldeenmansour123/Al-Protocol-Wal-Marasim
- **سير العمل:** `.github/workflows/build.yml` — الاسم الظاهر في Actions:
  «Build PROTOCOL & CEREMONIAL APK»
- **الحالة وقت كتابة هذا الدليل:** **لم يعمل سير العمل بعد ولا مرة.**
  الدفع إلى المستودع معلَّق على منح المستخدم صلاحية تطبيق GitHub، ولم
  يُدفع أي كود. كل ما يلي إجراءات *للتنفيذ بعد منح الصلاحية*، وليس سجل
  تشغيل ناجح. لا يُدَّعى نجاح أي بناء قبل ظهوره أخضر في Actions.

## 1. الدفع الأول (بعد منح صلاحية تطبيق GitHub)

> نفّذ هذه الخطوات من الجهاز الذي يملك نسخة العمل المحلية
> `~/workspace/protocol/repo/`، وبعد تأكيد المستخدم منح الصلاحية فقط.

```sh
cd ~/workspace/protocol/repo

# 1) تحقق أنك على الفرع الصحيح (السير يعمل على main و master)
git status
git branch --show-current        # المتوقع: main

# 2) تحقق أن المستودع البعيد هو المستودع الصحيح حرفياً
git remote -v
# المتوقع:
# origin  https://github.com/ezzaldeenmansour123/Al-Protocol-Wal-Marasim.git

# 3) تحقق أن لا ملفات ثنائية ستُدفع (يجب أن تكون القائمة نصية فقط:
#    .dart/.md/.json/.yaml/.py — لا .db ولا .ttf ولا .png ولا .apk)
git status --short
git ls-files --cached | grep -Ei '\.(db|ttf|otf|png|jpg|jpeg|apk|aab|onnx|tflite|gguf|bin|pt|safetensors)$' \
  && echo 'توقف: ملفات ثنائية في الفهرس — لا تدفع' || echo 'OK: لا ملفات ثنائية'

# 4) إن لم يكن المجلد مستودع git بعد، أو لم يكن البعيد مضبوطاً:
git init -b main                                   # فقط إن لم يوجد .git
git remote add origin https://github.com/ezzaldeenmansour123/Al-Protocol-Wal-Marasim.git
git add -A
git commit -m "PROTOCOL & CEREMONIAL: initial P6 push"

# 5) الدفع الأول
git push -u origin main
```

**ملاحظات الدفع الأول:**

- إن رفض الدفع بخطأ صلاحية (403)، **لا تعيد المحاولة تكراراً** — شخّص
  أولاً: هل الصلاحية مُنحت فعلاً لتطبيق GitHub؟ هل الحساب المسجّل هو
  الحساب المالك للمستودع؟ ثم أبلغ المستخدم بنص الخطأ حرفياً.
- إن كان المستودع البعيد يحوي ملفات أصلاً (مثلاً `README.md` من إنشاء
  GitHub)، اسحب أولاً وأدمج قبل الدفع:
  `git pull --rebase origin main` ثم أعد `git push`.
- ملف `.gitignore` يستبعد الثنائيات (انظر §5 أدناه). إن ظهر ملف ثنائي
  في `git status` رغم ذلك، أوقف الدفع وأصلح `.gitignore` أولاً.

## 2. كيف يُشغَّل سير العمل

سير العمل معرّف في `.github/workflows/build.yml` بمشغّلين:

```yaml
on:
  push:
    branches: [main, master]
  workflow_dispatch:
```

| المشغّل | متى يعمل |
|---|---|
| **تلقائي** | عند كل `git push` إلى `main` أو `master` (أي دفع، بما فيه الدفع الأول) |
| **يدوي** | من تبويب Actions في GitHub ← اختر «Build PROTOCOL & CEREMONIAL APK» ← زر «Run workflow» ← اختر الفرع ← «Run workflow». يُستخدم لإعادة البناء دون دفع جديد (مثلاً بعد إصلاح خارجي كعطل تنزيل خطوط مؤقت) |

لا يوجد تشغيل مجدول (`schedule`) ولا تشغيل عند Pull Request — الدفع إلى
فرع آخر غير `main`/`master` **لا** يشغّل البناء.

## 3. أين تُراقب حالة البناء

1. افتح المستودع في المتصفح:
   https://github.com/ezzaldeenmansour123/Al-Protocol-Wal-Marasim
2. تبويب **Actions** ← تشغيل «Build PROTOCOL & CEREMONIAL APK» الأحدث.
3. داخل التشغيل: مهمة واحدة `build` على `ubuntu-latest`، فيها الخطوات
   بالترتيب التالي (احفظ هذا الترتيب — به يُشخَّص أي فشل):

| # | الخطوة (كما تظهر في Actions) | ماذا تفعل |
|---|---|---|
| 1 | `Set up Java 17` | Temurin 17 |
| 2 | `Set up Flutter 3.50.1` | Flutter stable 3.50.1 |
| 3 | `Build protocol database` | `python3 tools/build_db.py tools/seed assets/marasim.db` ثم `ls -lh` |
| 4 | `Download Amiri and Cairo fonts` | تنزيل خطي Amiri وCairo من Google Fonts + التحقق أنها TTF حقيقية |
| 5 | `Download hero photos` | تنزيل 8 صور من Unsplash (أو توليد بدائل PIL عند الفشل — لا يفشل البناء) |
| 6 | `Generate app logo (assets/logo.png)` | توليد الشعار من `tools/make_icon.py` |
| 7 | `Create Android project files` | `flutter create --platforms=android` + تعديل Manifest + desugaring + أيقونة |
| 8 | `Get dependencies` | `flutter pub get` |
| 9 | `Analyze` | `flutter analyze` |
| 10 | `Test` | `flutter test` لغلافي الاسترجاع وحارس الرفض |
| 11 | `Build release APK` | `flutter build apk --release` |
| 12 | `Rename APK` | نسخ الناتج إلى `Protocol_Ceremonial.apk` |
| 13 | `Upload APK artifact` | رفع القطعة الأثرية `protocol-ceremonial-apk` |
| 14 | `Publish GitHub Release` | نشر Release بالوسم `build-N` (يحتاج `permissions: contents: write`) |

علامة التشغيل: ✅ أخضر = نجح كاملاً؛ ❌ أحمر = فشل عند أول خطوة حمراء؛
🟡 أصفر = يعمل الآن. **انقر أول خطوة حمراء** واقرأ آخر 30–50 سطراً من
سجلها — التشخيص في §6 يبدأ من هناك دائماً.

## 4. كيف يُنزَّل ملف APK

طريقتان، بنفس الملف `Protocol_Ceremonial.apk`:

**أ) من الـRelease (الطريقة المفضلة للاختبار على الهاتف):**

1. تبويب **Releases** في المستودع (أو الصفحة الرئيسية ← قسم Releases).
2. افتح أحدث Release: «PROTOCOL & CEREMONIAL build N».
3. نزّل `Protocol_Ceremonial.apk` من قسم Assets.
4. تحقق قبل التثبيت: اسم الملف حرفياً `Protocol_Ceremonial.apk`، وأن
   رقم `N` يطابق رقم تشغيل Actions الذي راقبته في §3.

**ب) من قطعة Actions الأثرية (إن لم يُنشر Release):**

1. تبويب **Actions** ← التشغيل الناجح ← أسفل الصفحة قسم **Artifacts**.
2. نزّل `protocol-ceremonial-apk` (ملف ZIP يحوي `Protocol_Ceremonial.apk`).
3. ملاحظة: قطع Actions الأثرية لها مدة احتفاظ محدودة في GitHub؛
   الـRelease هو الأرشيف الدائم.

**بعد التنزيل:** ثبّت على جهاز حقيقي وابدأ `docs/AIRPLANE_TEST.md`.

## 5. كيف تُتحقق من أن قاعدة البيانات بُنيت داخل البناء

قاعدة البيانات **لا تُدفع أبداً** — تُبنى في كل تشغيل CI من
`tools/seed/*.json` قبل بناء Flutter. ترتيب الخطوات في `build.yml`
مؤكَّد بالقراءة (P6): خطوة «Build protocol database» هي الخطوة رقم 3،
قبل تنزيل الخطوط والصور وقبل `flutter create` و`flutter build apk`.
الأمر المنفَّذ حرفياً:

```sh
python3 tools/build_db.py tools/seed assets/marasim.db
ls -lh assets/marasim.db assets/marasim.db.sha256
```

للتحقق من تشغيل ناجح، افتح سجل خطوة «Build protocol database» وتأكد
من **كل** ما يلي:

1. لا يوجد سطر يبدأ بـ`ERROR:` — الباني «يفشل بصوت عالٍ» (`fail()`)
   عند أي خطأ تحقق، فيفشل التشغيل كاملاً بدل إنتاج قاعدة ناقصة.
2. سطور العدّ المتوقعة (القيم ثابتة في `tools/build_db.py`):
   - `articles: 49 (16 sections)`
   - `sources: 11` (8 موثَّقة + 3 غير موثَّقة — يطبعها الباني
     `sources: 11 (8 verified, 3 unverified)`)
   - `countries: 30 (national days: …)`
   - `templates: 7`
   - `kb_topics: 54 (36535 words, … topic-article links)`
   - `kb_corrections: … rules (… applications)`
   - `en_keywords: 54 topics, … terms` و`ar_keywords: … topics, … terms`
3. سطر الختام: `OK size=…MB sha256=…` متبوعاً بسطر `ls -lh` يظهر
   `assets/marasim.db` (~1.2MB محلياً وقت P6) و`assets/marasim.db.sha256`.
4. تحقق إضافي محلي بعد تنزيل الـAPK غير ممكن من الـAPK وحده؛ التحقق
   الوظيفي يكون بفتح الموسوعة والمساعد على الجهاز (انظر
   `docs/AIRPLANE_TEST.md` §2.1–2.2): صفر نتائج للبحث عن «الأسبقية»
   تعني قاعدة غير مضمّنة أو غير مُرحَّلة.

وإن أردت إعادة بناء القاعدة محلياً للمقارنة (لا تُدفع النتيجة):

```sh
python3 tools/build_db.py tools/seed /tmp/check.db
python3 tools/build_db.py --check /tmp/check.db
```

## 6. قائمة الأعطال الشائعة المتوقعة وكيفية تشخيصها من السجلات

| العطل | أين يظهر في السجل | التشخيص والإصلاح |
|---|---|---|
| **فشل تنزيل الخطوط** (Amiri/Cairo) | خطوة «Download Amiri and Cairo fonts» حمراء؛ `RuntimeError: Amiri download failed …` أو `Cairo download/instancing failed …` | الخطوط غير ملتزمة في المستودع عمداً، ففشل التنزيل يوقف البناء **بالتصميم** (لا APK بلا خطوط). تحقق: هل الرابط في Google Fonts ما زال يعمل؟ هل هي مشكلة شبكة مؤقتة في العدّاء؟ أعد التشغيل يدوياً (`workflow_dispatch`)؛ إن تكرر، افتح الرابط في المتصفح وتحقق من مسار الملف في `github.com/google/fonts`. لا تلتزم ملفات TTF في المستودع كـ«إصلاح سريع». |
| **الاستيراد الدائري `main.dart` ↔ `sections.dart`** | خطوة «Analyze» أو «Build release APK» حمراء؛ أخطاء استيراد/تعريف مكرر تشير إلى `lib/main.dart` و`lib/sections.dart` | الحالة مؤكدة بالقراءة (P6): `lib/main.dart:12` يستورد `sections.dart`، و`lib/sections.dart:8` يستورد `main.dart`. Dart يسمح بالاستيراد الدائري لكنه هشّ (أخطاء تحليل غامضة عند إعادة التهيئة). التشخيص: ابحث في السجل عن `main.dart` و`sections.dart` معاً. الإصلاح الجذري: كسر الحلقة بنقل التعريفات المشتركة إلى ملف ثالث (مهمة تطوير، ليست إصلاح CI). إن ظهر الخطأ فجأة بعد تغيير في أحد الملفين، راجع آخر تعديل عليهما أولاً. |
| **فشل `flutter create` أو تعديل Manifest** | خطوة «Create Android project files» حمراء؛ `assert` فشل (مثلاً `android.permission.INTERNET not in t` أو `compileSdk = flutter.compileSdkVersion`) | سكربت الخطوة يفترض قالب `flutter create` لإصدار Flutter 3.50.1 حرفياً. إن غيّرت نسخة Flutter السلوك/القالب، راجع الـassert الفاشل وحدّث السكربت ليطابق القالب الجديد. لا تعدّل نسخة Flutter في `build.yml` دون تحديث هذا السكربت. |
| **فشل `flutter analyze`** | خطوة «Analyze» حمراء؛ قائمة مشاكل `info/warning/error` | اقرأ أول خطأ `error` (التحذيرات `info` قد لا تفشل البناء حسب الإعداد). أصلح الكود محلياً وادفع من جديد. لا تُسكت المحلل بإضافة استثناءات دون مراجعة. |
| **فشل `flutter test`** | خطوة «Test» حمراء؛ اسم الفحص الفاشل من `retrieval_core_test.dart` أو `refusal_guard_test.dart` | محلياً: `dart test/retrieval_core_test.dart` و`dart test/refusal_guard_test.dart` (تعملان بلا Flutter SDK — انظر `test/README.md`). إن نجحا محلياً وفشلا في CI، فالفرق غالباً في بيئة Flutter/الملفات المولّدة — قارن إصدار Dart. |
| **فشل `flutter build apk`** (أخطاء Gradle/Kotlin) | خطوة «Build release APK» حمراء؛ ذيل السجل يحوي `FAILURE: Build failed` | انسخ أول سطر `e:` (خطأ Kotlin) أو `error:` من السجل. الأسباب الشائعة: عدم توافق إصدار إضافة مع `compileSdk 36` (مثبّت عمداً: `flutter_local_notifications 22.3.3` لأن 23.x يحتاج SDK 37 غير المتوفر في العدّاء — انظر تعليق `pubspec.yaml`)؛ أو نقص ذاكرة العدّاء. لا ترفع `compileSdk` دون التحقق من توفر SDK 37 في العدّاء. |
| **فشل نشر الـRelease** | خطوة «Publish GitHub Release» حمراء رغم نجاح البناء؛ `403` أو `Resource not accessible by integration` | الخطوة تستخدم `softprops/action-gh-release@v2` وتحتاج `permissions: contents: write` (موجود في `build.yml`). إن فشلت رغم ذلك، تحقق أن تطبيق GitHub المانح للصلاحية يملك صلاحية المحتوى (Contents: write)، وأن الوسم `build-N` غير موجود مسبقاً. الـAPK يبقى متاحاً كقطعة أثرية (§4ب) حتى لو فشل النشر. |
| **صور Unsplash تفشل** | خطوة «Download hero photos» تطبع `download failed …; generating placeholder` | **ليس عطلاً**: الخطوة تولّد بدائل PIL (كحلي/ذهبي) ولا تفشل البناء أبداً بالتصميم. إن ظهرت كل الصور بدائل، فالـAPK يعمل لكن بصور بديلة — سجّلها ملاحظة، لا فشلاً. |
| **فشل `flutter pub get`** | خطوة «Get dependencies» حمراء؛ `version solving failed` | غالباً تغيير في `pubspec.yaml`/`pubspec.lock` غير متوافق. لا تحذف `pubspec.lock` من المستودع؛ حلّ التعارض محلياً بـ`flutter pub get` (يحتاج Flutter SDK) أو راجع آخر تعديل على `pubspec.yaml`. |
| **التشغيل لا يبدأ أصلاً** | لا يظهر تشغيل جديد في Actions بعد الدفع | تحقق: هل الدفع كان إلى `main` أو `master` فعلاً؟ هل ملف `build.yml` سليم YAML (خطأ بنيوي يمنع ظهور السير)؟ هل الصلاحية ما زالت ممنوحة؟ افحص تبويب Actions ← «Workflows» — سير فيه خطأ بنيوي يظهر بعلامة تحذير. |

## 7. قاعدة ذهبية

- **لا يُقال «البناء نجح» إلا بعد ظهور التشغيل أخضر كاملاً في Actions
  وظهور الـRelease `build-N` وفيه `Protocol_Ceremonial.apk`.**
- أي تعديل على `build.yml` أو `tools/build_db.py` أو `pubspec.yaml`
  يستدعي إعادة قراءة هذا الدليل والتحقق من §5 (ترتيب بناء القاعدة)
  قبل الدفع.
- سجّل كل تشغيل أول (رقمه، نتيجته، أي فشل ونصه) في ملاحظات المرحلة
  `~/workspace/protocol/PHASE6_TEAM3_NOTES.md` أو خلفها.
