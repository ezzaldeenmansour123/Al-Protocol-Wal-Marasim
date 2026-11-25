# تقرير بناء قاعدة البيانات v2 — PROTOCOL & CEREMONIAL

- **التاريخ:** 2026-11-25 (Asia/Aden) — ملاحظة: حقل `meta.built` في القاعدة سجّل `2026-11-24` لأن ساعة الجهاز الافتراضي UTC؛ الباني يستخدم `datetime.date.today()` كما في v1.
- **النطاق:** `~/workspace/protocol/repo/` محلياً فقط — لا GitHub ولا دفع ولا شبكة. المجلد ليس مستودع git محلياً (لا يوجد `.git`)، فلا يوجد ما يُدفع أصلاً.
- **المصدر المرجعي للتنفيذ:** `KNOWLEDGE_BASE_REPORT.md §5` (مخطط جداول قاعدة المعرفة) + `IMPLEMENTATION_PLAN.md §1–§2` (جدول `sources` والفئات الخمس).

## 1. الأوامر المنفذة

```bash
# نسخ ملفات البذور إلى المستودع (بصمات SHA-256 مطابقة للأصول)
cp ~/workspace/protocol/book/knowledge_base/knowledge_base.json   tools/seed/knowledge_base.json        # 615K
cp ~/workspace/protocol/sources/INTERNATIONAL_SOURCES.json        tools/seed/sources.json
cp ~/workspace/protocol/book/knowledge_base/corrections_log.json  tools/seed/corrections_log.json
cp ~/workspace/protocol/sources/ARTICLE_SOURCE_MAP.md             tools/seed/article_source_map.md

# البناء والتحقق
python3 tools/build_db.py tools/seed assets/marasim.db
python3 tools/build_db.py --check assets/marasim.db
# تحقق مستقل بـ sqlite3/python: سلامة، مفاتيح أجنبية، مطابقة حرفية لكل موضوعات الـ54 مع JSON،
# توزيع الحالات، قواعد source_url، جداول المستخدم الفارغة، وعدّ نتائج FTS الخمسة الكامل
# اختبار سلبي للفشل بصوت عالٍ: نسخة بذور في /tmp بمحور 9 للمقال 1
python3 tools/build_db.py /tmp/seedtest /tmp/bad.db   # -> ERROR + exit 1، ولم يُنتَج ملف
```

**سير عمل CI:** لم يُعدَّل `repo/.github/workflows/build.yml` — استدعاء الباني فيه ما زال
`python3 tools/build_db.py tools/seed assets/marasim.db` ولم يتغير، والباني يقرأ الملفات
الجديدة من `tools/seed/` نفسها (مع مسار بديل `../../../book/...` و`../../../sources/...`
للتطوير المحلي فقط إن غابت من البذور).

## 2. الملفات المغيَّرة / المضافة

| الملف | التغيير |
|---|---|
| `tools/build_db.py` | أُعيدت كتابته إلى v2 (انظر §3) |
| `tools/seed/knowledge_base.json` | جديد — نسخة حرفية من قاعدة المعرفة (54 موضوعاً) |
| `tools/seed/sources.json` | جديد — نسخة حرفية من سجل المصادر (11 مصدراً) |
| `tools/seed/corrections_log.json` | جديد — سجل التصحيحات (مصدر `kb_corrections`؛ يلزم CI لبنائه) |
| `tools/seed/article_source_map.md` | جديد — خريطة الربط؛ الباني يحلل جدولها برمجياً (يلزم CI لبنائه) |
| `assets/marasim.db` | جديد — أُعيد بناؤه (1.2MB)؛ ملاحظة: `.gitignore` يستثنيه (يُبنى في CI) |
| `assets/marasim.db.sha256` | جدّد: `01ccf83b2c5a52bcb2e57e6aaef22aec46d57348446bf7a5e764cf4c7c5435b5` |
| `tools/DB_BUILD_REPORT.md` | هذا التقرير |

## 3. ما فعله الباني v2

- **المقالات/الدول/القوالب كما هي:** 49 مقالاً، 30 دولة، 7 قوالب، 16 قسماً، 29 يوماً وطنياً — لا حذف.
- **أعمدة جديدة في `articles`:** `source_code TEXT, axis INTEGER, section_code TEXT, source_status TEXT`،
  تُملأ بتحليل جدول `ARTICLE_SOURCE_MAP.md` برمجياً (محور من عمود «المحور»، ورمز المبحث من عمود
  «المبحث» بصيغة `بN فN مN`، وأول رمز مقترح من عمود «المصدر الدولي المقترح»، والحالة من الإيموجي).
- **`sources` جديد** (مخطط `IMPLEMENTATION_PLAN.md §1`: `id, code UNIQUE, name_ar, name_en, publisher,
  url, classification, scope, verified, review_date`) مبذور من `sources.json`: 11 مصدراً
  (8 متحقق `verified=1` بروابطها، 3 غير متحقق `verified=0` و`url=''` — لا رابط مخزّن لأي مصدر غير متحقق).
  ملاحظة: مصدر `UN-CHARTER` ليس له حقل `url` في السجل بل `url_ar`/`url_en`؛ خُزّن الرابط العربي
  (وهو نفس رابط `source_url` الحالي للمقال 2).
- **جداول قاعدة المعرفة من KB report §5 حرفياً:** `kb_topics` (30 عموداً كما في §5)،
  `kb_topic_articles` (direct/nearest)، `kb_corrections` (من `corrections_log.json`)،
  `kb_topics_fts` (FTS5 على `title/summary/definition/explanation` مع `content='kb_topics'`).
  الفهرس يُبنى من نص مطبَّع بنفس تطبيع `search_norm` المستخدم في `articles_fts` لتطابق استعلامات التطبيق؛
  **لا يُشغَّل `rebuild` على هذا الجدول أبداً** (سيعيد فهرسة النص الخام غير المطبَّع ويكسر البحث المطبَّع) — موثّق في تعليق بالكود.
  جدول `kb_sources` الوارد في §5 لم يُنشأ كجدول منفصل: جدول `sources` يؤدي دوره بنفس السجلات الـ11
  وبمخطط أغنى (`classification/scope/review_date`) حسب `IMPLEMENTATION_PLAN.md §1`.
- **`meta.db_version='2'`** + حقول جديدة: `kb_topics=54`، `kb_words=36535`، `kb_corrections=1310`،
  `kb_sources_verified=8`، `kb_sources_unverified=3`، `kb_source` (بيانات الكتاب الببليوغرافية)،
  و`kb_text_status_note` الذي ينص صراحةً أن «مصحح آلياً» لا تعني مراجعة بشرية كاملة للنص.
- **فحوصات فشل بصوت عالٍ (جديدة):** عدد الموضوعات = 54 تماماً، مجموع الكلمات = 36535، كل موضوع
  بعنوان و`pdf pages` صالحة و`book pages` صالحة (كلاهما null أو كلاهما عددان صحيحان؛ الوحيد بلا ترقيم
  مطبوع هو `FM-01` وله `book_page_label`)، لا رمز مصدر خارج جدول `sources`، لا `source_url` لمقال
  حالته ليست `verified` (ولا مقال `verified` بلا رابط)، محور خارج 1–7 يفشل، مقال بلا محور يفشل،
  مجموع التصحيحات (1310) مطابق بين الموضوعات وسجل التصحيحات، وعدد صفوف FTS المفهرسة = 54.

## 4. نتائج التحقق (على `assets/marasim.db` المبنية)

- `PRAGMA integrity_check` = **ok**؛ `foreign_key_check` = فارغ.
- **العدّ:** `kb_topics=54`، `articles=49`، `countries=30`، `templates=7`، `national_days=29`،
  `sources=11`، `kb_topic_articles=70` (43 direct + 27 nearest)، `kb_corrections=91` قاعدة (1310 تطبيقاً)،
  `meta.db_version=2`.
- **المقالات:** الحالات `verified=10, proposed=32, none=7`؛ المحاور 1–7 بتوزيع (2، 7، 4، 12، 5، 8، 11)؛
  لا مقال بلا `axis` أو `section_code`؛ `source_url` معبّأ للمقالات العشر فقط (2، 3، 4، 5، 6، 7، 8، 36، 40، 48)؛
  صفر `source_url` لمقال غير `verified`؛ صفر روابط في `sources` لمصدر `verified=0`.
- **قاعدة المعرفة:** مجموع الكلمات 36535؛ الحالات `مصحح آلياً=53` و`ناقص — نص جزئي (صور غير مستخرجة)=1`
  (P2C1-M4V)؛ المطابقة `مباشر=15، الأقرب=6، فجوة=33`؛ لا موضوع بلا عنوان؛ لا `pdf pages` ناقصة؛
  **مطابقة حرفية 54/54 موضوعاً** مع `knowledge_base.json` (العنوان، الباب/الفصل/المبحث، الملخص، التعريف،
  الشرح، صفحات الكتاب وPDF، عدد الكلمات/الحروف، الحالة، المطابقة) — صفر اختلافات؛ وفحص عينة لتدوير
  حقول JSON (subsections/rules/key_points) سليم. `definition` قيمتها NULL في 37 موضوعاً و`explanation`
  NULL في موضوع واحد — وهذا متعمَّد حسب تقرير قاعدة المعرفة (NULL تعني أن العنصر لم يرد في نص المبحث).
  حقل `correction_detail` التفصيلي لكل موضوع **لم يُخزَّن** (لا عمود له في مخطط §5)؛ المجمَّع في `kb_corrections`.
- **جداول بيانات المستخدم موجودة فارغة:** `favorites=0, events=0, event_guests=0, event_program=0,
  checklist_items=0, seating_plans=0, seating_assignments=0, settings=0`.
- **استعلامات FTS5 الخمسة على `kb_topics_fts`** (استعلامات مطبَّعة بنفس منطق التطبيق؛ كل نتيجة برقم صفحة الكتاب):

| السؤال | إجمالي النتائج | أبرز النتائج (مع صفحات الكتاب) |
|---|---|---|
| الأسبقية | 27 | P2C1-M2-00 (54–55)، P2C1-M2-01 (56–60)، P2C1-M2-02 (61–64) ضمن النتائج |
| تقديم أوراق اعتماد السفراء | 5 | **P2C3-M2** مراسم تقديم أوراق اعتماد السفراء (199–204)؛ P2C1-M2-04 (69–71) |
| مراسم توديع كبار الشخصيات | 2 | **P2C1-M5** مراسم توديع كبار الشخصيات (126–135)؛ P2C1-X (140) |
| الأعلام والنشيد | 3 | **P2C2-M3** مراسم الأعلام والنشيد والشعار الوطني (164–176) |
| الزيارات الرسمية | 13 | **P2C1-M3** تنظيم الزيارات الرسمية واستراتيجياتها (94–98) ضمن النتائج |

  ملاحظة ترتيب: أول 3 نتائج المعروضة في `--check` ليست دائماً الموضوع الأساسي (مثلاً «الأسبقية» تعيد
  FM-01 أولاً) لأن ترتيب BM25 يعتمد على تكرار المصطلحات؛ الموضوعات الأساسية موجودة كلها ضمن النتائج.
  تحسين الترتيب (تقديم الموضوع المطابق للعنوان) مهمة لاحقة لطبقة الاسترجاع، لا للباني.

## 5. فشل / تحذيرات / ملاحظات مسجَّلة

1. **فشل أول بناء ثم إصلاحه:** البناء الأول فشل بـ `table kb_topics has 30 columns but 29 values were supplied`
   (عدد العناصر النائبة في INSERT كان 29)؛ صُحّح إلى 30 وأُعيد البناء بنجاح. لا أثر متبقٍ.
2. **إحصاءات رأس خريطة الربط لا تطابق جدولها:** رأس `ARTICLE_SOURCE_MAP.md` يقول 26 مقترحاً و13 بلا مصدر،
   بينما صفوف الجدول نفسه تعطي **32 مقترحاً و7 بلا مصدر** (و10 موثقاً في الحالتين). الباني حلّل الصفوف
   (المصدر الموثوق) وتجاهل إحصاءات الرأس؛ يُنصح بتصحيح الرأس في ملف الخريطة لاحقاً.
3. **المقال 48 — موثّق جزئياً:** حالته `verified` (ضمن العشر ✅) لكن `source_code` = NULL لأن اتفاقية فيينا
   لقانون المعاهدات 1969 ليست في سجل المصادر، و`source_url` الحالي `https://treaties.un.org/` بوابة عامة
   لا وثيقة محددة (كما تنص الخريطة نفسها). لم يُخترع له رابط؛ يحتاج رابطاً محدداً متحققاً للاتفاقية قبل
   تثبيت `source_code`.
4. **المقالات الـ7 بلا مصدر (`none`):** 18، 31، 32، 33، 34، 46، 47 — `source_code` NULL و`source_url` فارغ، كما تقتضي القاعدة.
5. **صيغة ملف `.sha256`:** الباني (v1 كما هو) يكتب البصمة وحدها بلا اسم ملف، فأمر `sha256sum -c` لا يقبلها؛
   تم التحقق يدوياً بأن محتوى الملف يساوي بصمة `assets/marasim.db`. الصيغة موروثة ولم تُغيَّر.
6. **لم يُعدَّل `lib/` إطلاقاً** — الترحيل الفعلي مهمة زميل آخر (انظر §6).

## 6. مخطط الترحيل المقترح 1→2 (لزميل `lib/db.dart` — مقترح فقط، لم يُنفَّذ هنا)

```dart
openDatabase(path, version: 2,
  onCreate: (db, v) async { /* إنشاء المخطط v2 كاملاً من الأصول */ },
  onUpgrade: (db, oldVersion, newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        // 1) إنشاء الجداول الجديدة: sources, kb_topics, kb_topic_articles,
        //    kb_corrections, kb_topics_fts (نفس DDL في tools/build_db.py).
        // 2) إضافة الأعمدة إلى articles:
        //    ALTER TABLE articles ADD COLUMN source_code TEXT;
        //    ALTER TABLE articles ADD COLUMN axis INTEGER;
        //    ALTER TABLE articles ADD COLUMN section_code TEXT;
        //    ALTER TABLE articles ADD COLUMN source_status TEXT;
        // 3) تعبئة الجداول الجديدة والأعمدة من نسخة الأصول الجديدة
        //    (assets/marasim.db) — قراءة من قاعدة الأصول المرفقة لا من الشبكة.
        // 4) تحديث meta.db_version إلى '2'.
        // كل ذلك داخل transaction واحدة؛ بيانات المستخدم
        // (favorites, events, seating_plans, settings...) لا تُمسّ ولا تُستبدل.
      });
    }
  });
```

- **لا استبدال أعمى** لقاعدة المستخدم بملف الأصول: النسخ الكامل يمحو المناسبات وخطط الجلوس والمفضلات.
- عند بدء التشغيل تُقارن `db_version` (أو بصمة `assets/marasim.db.sha256`) بنسخة الأصول؛ عند الاختلاف
  يُرحَّل المحتوى فقط وتُنقَل بيانات المستخدم كما هي.
- أي إصدار لاحق يرفع `db_version` ويرفقه بترحيل متسلسل موثق (`onUpgrade` يتعامل مع كل قفزة إصدار).

## 7. ما لم يُختبر (بصراحة)

- **لا `flutter analyze` ولا بناء APK ولا اختبار على جهاز** — لا Flutter/Android SDK محلياً؛
  سير عمل CI لم يُشغَّل (لا شبكة ولا GitHub من هذه المهمة).
- **الترحيل 1→2 لم يُنفَّذ ولم يُختبر** على قاعدة مستخدم حقيقية من v1: ملف `assets/marasim.db` القديم
  غير موجود محلياً أصلاً (يوجد فقط `marasim.db.sha256` القديم)، فلا نسخة v1 محلية لاختبار الترحيل عليها.
  المخطط في §6 مقترح فقط ويحتاج اختبار تثبيت-فوق-نسخة-قديمة على جهاز.
- **لم يُختبر تكامل `lib/db.dart` مع الأعمدة/الجداول الجديدة** (قراءة `articles.source_code/axis/...`
  و`kb_topics_fts` من Dart) — خارج نطاق هذه المهمة (`lib/` لزميل آخر).
- **جودة ترتيب نتائج FTS** لم تُقيَّم beyond وجود النتائج (§4)؛ مجموعة اختبار الـ100 سؤال لم تُنفَّذ هنا.
- **المراجعة البشرية للمحتوى** لم تتم: حالة «مصحح آلياً» تنبيهها في `meta.kb_text_status_note`؛
  والروابط المقترحة 🔍 ما زالت بلا `source_url` بانتظار المراجعة البشرية كما تقتضي الخطة.

---

## ملحق R1 — جولة التحسين 1 للاسترجاع (2026-11-25)

- **القاعدة الجديدة:** أُعيد بناؤها بالباني نفسه
  (`python3 tools/build_db.py tools/seed assets/marasim.db`)،
  sha256 `31f02410a1bff10774e2ad8084bf8f43d1f0129260dd9e24a692ec339edd237b`
  (كان `01ccf83b…`)، الحجم 1.17MB.
- **عمودان جديدان في `kb_topics`:** `en_keywords TEXT` (مفردات إنجليزية
  للمواضيع الـ54، 463 مصطلحاً، من `tools/seed/kb_en_keywords.json`) و
  `ar_keywords TEXT` (مفردات عربية لـ5 مواضيع، 19 مصطلحاً، من
  `tools/seed/kb_ar_keywords.json`). التحقق صارم ويفشل بصوت عالٍ:
  تغطية إنجليزية 54/54 بالضبط، وكل مفردة عربية يجب أن ترد في نص
  موضوعها المستخرج (أُثبت باختبارين سلبيين: مفردة إنجليزية غير
  صغيرة/برمز سيئ، ومفردة عربية «وفد» غير واردة في نص الاستقبال —
  كلاهما خروج 1 وبلا ملف).
- **مخطط FTS بلا تغيير عمداً:** `kb_topics_fts` ما زال بأعمدته الأربعة؛
  العنوان المفهرس هو `search_norm(title + en_keywords + ar_keywords)`.
  لا يُشغَّل `('rebuild')` على الجدول إطلاقاً — سيُسقط المفردات.
  `meta` جديدة: `kb_en_keywords_topics=54` و`kb_en_keywords_terms=463`
  و`kb_ar_keywords_topics=5` و`kb_ar_keywords_terms=19`.
- **بقية المخطط والعدد بلا تغيير:** 49 مقالاً، 30 دولة، 7 قوالب،
  54 موضوعاً، 36535 كلمة، 70 رابط موضوع-مقال، 91 قاعدة تصحيح
  (1310 تطبيقاً)، 11 مصدراً (8 متحقق + 3 غير متحقق). `meta.built`
  ما زال يسجل تاريخ UTC للجهاز (2026-11-24) — تجميلي ومعروف.
- **القياس:** انظر `test_data/MEASUREMENT_R1.md` — hit@3 من 63.7%
  (51/80) إلى 100% (80/80) بالعدّاد نفسه.
