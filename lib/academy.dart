// ── الأكاديمية والتدريب (CHARTER_V2 §7 + V2_PLAN §1.4) ──
//
// تنبيه ربط (للمتخصص بالتنسيق — لا يُعدَّل هنا):
//  • AcademyPage الحقيقية هنا (lib/academy.dart:384) وهي المستوردة
//    في lib/main.dart؛ لا يوجد عنصر نائب بهذا الاسم في
//    lib/sections.dart (أُزيل استيراد academy.dart غير المستخدم منه).
//  • جداول الأكاديمية في lib/academy_db.dart؛ ويستدعي المنسّق
//    createAcademyTables() من _ensureV2Schema في db.dart، أو تكفي
//    ensureAcademyTables() عند أول فتح للأكاديمية (تُستدعى من هنا).
//
// قاعدة المحتوى الصارمة (ملزمة):
//  • الدرس = مبحث كتاب: عنوانه حرفياً من kb_topics، ورابط topic_id،
//    ومواضيع داعمة من kb_topics فقط. لا يُكتب أي جسم تعليمي هنا؛ جسم
//    الدرس موسوم حرفياً «قيد الإعداد — بانتظار المراجعة البشرية»
//    (kAcademyLessonPendingLabel) ولا يُنسب أي نص للكتاب قبل تلك المراجعة.
//  • ما تعرضه LessonPage من قاعدة المعرفة (تعريف/شرح/قواعد/إجراءات/
//    أمثلة/أخطاء) هو حقول kb_topics نفسها، موسومة «من قاعدة المعرفة»
//    مع حالة نصها (مصحح آلياً — لم تُراجَع بشرياً)، ويُعرض منها ما ورد
//    فعلاً فقط؛ فغياب حقل يعني أنه لم يرد في نص المبحث لا أنه غير موجود.
//  • بنك الأسئلة (academy_db.dart): سؤال بنيوي واحد لكل درس عن موضع
//    المبحث (باب/فصل/صفحة) وإجابته حقل من kb_topics، موسوم كله
//    «قيد المراجعة البشرية». لا سؤال ولا إجابة ولا شرح مخترَع منسوب للكتاب.
//  • السيناريوهات: عناوين مهام تطبيقية عامة + رابط أداة عاملة؛ نص
//    الحالة الدراسية نفسه «قيد الإعداد — بانتظار المراجعة البشرية».
//  • تقييم المستوى: نتيجة محسوبة من سجل التقدم المحلي فقط (دروس مكتملة
//    ونتائج اختبارات)، لا اختبار دخول مخترَع ولا تقدير بلا بيانات.
//  • نصوص الواجهة الجديدة ألفاظ عربية صريحة في هذا الملف؛ مفاتيح الترجمة
//    في app_state.dart لا يملك هذا الفريق تعديلها، فيضيفها المنسّق إن
//    أراد مطابقة إنجليزية (الواجهة الإنجليزية تعرض العربية هنا مؤقتاً).
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'academy_db.dart';
import 'app_state.dart';
import 'db.dart';
import 'encyclopedia.dart';
import 'tools.dart';
import 'widgets.dart';

// ── الأداة المرتبطة بالدرس/السيناريو (صفحات عاملة قائمة) ──

enum AcademyTool { none, precedence, seating, events, docs, checker }

extension AcademyToolUi on AcademyTool {
  String get labelAr {
    switch (this) {
      case AcademyTool.precedence:
        return 'أداة الأسبقية الرسمية';
      case AcademyTool.seating:
        return 'أداة ترتيب الجلوس';
      case AcademyTool.events:
        return 'أداة تنظيم المناسبات والزيارات';
      case AcademyTool.docs:
        return 'أداة المخاطبات والمستندات';
      case AcademyTool.checker:
        return 'فاحص البروتوكول';
      case AcademyTool.none:
        return '';
    }
  }

  Widget page() {
    switch (this) {
      case AcademyTool.precedence:
        return const PrecedencePage();
      case AcademyTool.seating:
        return const SeatingPlansPage();
      case AcademyTool.events:
        return const EventsPage();
      case AcademyTool.docs:
        return const DocGeneratorPage();
      case AcademyTool.checker:
        return const CheckerPickerPage();
      case AcademyTool.none:
        throw StateError('AcademyTool.none has no page');
    }
  }
}

// ── المستويات والكتالوج (مشتق من BOOK_INDEX.md + kb_topics) ──

class AcademyLevel {
  final int id;
  final String titleAr, subAr;
  const AcademyLevel(this.id, this.titleAr, this.subAr);
}

const List<AcademyLevel> kAcademyLevels = [
  AcademyLevel(1, 'المستوى الأول: الأسس النظرية والتاريخية',
      'الباب الأول — الفصلان الأول والثاني: مفاهيم + تاريخ'),
  AcademyLevel(2, 'المستوى الثاني: إدارة المراسم الرسمية في الدولة',
      'الباب الثاني — الفصل الأول'),
  AcademyLevel(3, 'المستوى الثالث: الممارسات التطبيقية والدبلوماسية',
      'الباب الثاني — الفصلان الثاني والثالث'),
];

class AcademyLesson {
  final String id;
  final int level;
  final String title;
  final String topicId;
  final List<String> supportingTopicIds;
  final AcademyTool tool;
  const AcademyLesson(
    this.id,
    this.level,
    this.title,
    this.topicId, {
    this.supportingTopicIds = const [],
    this.tool = AcademyTool.none,
  });
}

/// 31 درساً. العدّ: 9 (الباب الأول) + 14 (الباب الثاني ف1: المبحث الأول
/// + جوانب الأسبقية الثمانية + المباحث 3–6 + الملخص البصري للاستقبال)
/// + 8 (الباب الثاني ف2–ف3). العناوين حرفياً من kb_topics؛ والصفحات
/// في بذرة الأسئلة (academy_db.dart) متحقق منها ضد قاعدة المعرفة.
/// مواضيع داعمة لا دروساً مستقلة: P2C1-M2-00 (مقدمة الأسبقية)،
/// P2C1-M2-09 (تعارض المعايير)، P2C1-M2-10 (خلاصة الجوانب الثمانية).
const List<AcademyLesson> kAcademyLessons = [
  // المستوى الأول — الباب الأول: مفاهيم + تاريخ (9 دروس).
  AcademyLesson('L1-01', 1, 'تعريف المراسم', 'P1C1-M1'),
  AcademyLesson('L1-02', 1, 'تعريف البروتوكولات', 'P1C1-M2'),
  AcademyLesson('L1-03', 1, 'تعريف التشريفات', 'P1C1-M3'),
  AcademyLesson(
      'L1-04', 1, 'الفروق بين المراسم والبروتوكولات والتشريفات', 'P1C1-M4'),
  AcademyLesson('L1-05', 1,
      'الجذور الأولى للمراسم والبروتوكول في الحضارات القديمة', 'P1C2-M1'),
  AcademyLesson(
      'L1-06', 1, 'المراسم والبروتوكولات في العصر الإسلامي', 'P1C2-M2'),
  AcademyLesson('L1-07', 1,
      'المراسم والبروتوكول في العصور الوسطى وأوروبا الملكية', 'P1C2-M3'),
  AcademyLesson('L1-08', 1,
      'نشأة البروتوكولات الدبلوماسية الحديثة ومأسستها الدولية', 'P1C2-M4'),
  AcademyLesson(
      'L1-09', 1, 'المراسم المعاصرة وإدارة الصورة الذهنية', 'P1C2-M5'),
  // المستوى الثاني — الباب الثاني، الفصل الأول (14 درساً).
  AcademyLesson('L2-01', 2,
      'الهيكل المؤسسي لإدارة المراسم والبروتوكول في الدولة', 'P2C1-M1'),
  AcademyLesson('L2-02', 2, 'الأسبقية داخل الدولة', 'P2C1-M2-01',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-03', 2, 'الأسبقية بين الدول', 'P2C1-M2-02',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-04', 2, 'أسبقية الملوك ورؤساء الدول', 'P2C1-M2-03',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-05', 2, 'الأسبقية في مجال البعثات الدبلوماسية والقنصلية',
      'P2C1-M2-04',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-06', 2, 'الأسبقية في الأمم المتحدة', 'P2C1-M2-05',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-07', 2, 'الأسبقية في جامعة الدول العربية', 'P2C1-M2-06',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-08', 2, 'الأسبقية في المناسبات الرسمية', 'P2C1-M2-07',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-09', 2, 'أسبقية المجاملة', 'P2C1-M2-08',
      supportingTopicIds: ['P2C1-M2-00', 'P2C1-M2-09', 'P2C1-M2-10'],
      tool: AcademyTool.precedence),
  AcademyLesson('L2-10', 2, 'تنظيم الزيارات الرسمية واستراتيجياتها', 'P2C1-M3',
      tool: AcademyTool.events),
  AcademyLesson('L2-11', 2, 'مراسم استقبال كبار الشخصيات', 'P2C1-M4',
      supportingTopicIds: ['P2C1-M4V'], tool: AcademyTool.events),
  AcademyLesson('L2-12', 2, 'ملخص بصري لمراحل مراسم الاستقبال', 'P2C1-M4V',
      tool: AcademyTool.events),
  AcademyLesson('L2-13', 2, 'مراسم توديع كبار الشخصيات', 'P2C1-M5',
      tool: AcademyTool.events),
  AcademyLesson('L2-14', 2,
      'آلية ممارسة المراسم والبروتوكول في الجمهورية اليمنية', 'P2C1-M6'),
  // المستوى الثالث — الباب الثاني، الفصلان الثاني والثالث (8 دروس).
  AcademyLesson('L3-01', 3, 'بروتوكول المؤتمرات والاجتماعات الدولية', 'P2C2-M1',
      tool: AcademyTool.events),
  AcademyLesson('L3-02', 3, 'حفلات العشاء والمآدب الرسمية', 'P2C2-M2',
      tool: AcademyTool.seating),
  AcademyLesson('L3-03', 3, 'مراسم الأعلام والنشيد والشعار الوطني', 'P2C2-M3',
      tool: AcademyTool.checker),
  AcademyLesson('L3-04', 3, 'مراسم تقديم الهدايا والتوثيق الرسمي', 'P2C2-M4',
      tool: AcademyTool.docs),
  AcademyLesson(
      'L3-05', 3, 'الدبلوماسية والمراسم والبروتوكولات الدولية', 'P2C3-M1'),
  AcademyLesson('L3-06', 3, 'مراسم تقديم أوراق اعتماد السفراء', 'P2C3-M2',
      tool: AcademyTool.docs),
  AcademyLesson('L3-07', 3, 'بروتوكول توقيع الاتفاقيات والمعاهدات', 'P2C3-M3',
      tool: AcademyTool.docs),
  AcademyLesson(
      'L3-08', 3, 'البروتوكول في الاحتفالات الوطنية والدينية', 'P2C3-M4',
      tool: AcademyTool.events),
];

AcademyLesson? academyLessonById(String id) {
  for (final l in kAcademyLessons) {
    if (l.id == id) return l;
  }
  return null;
}

List<AcademyLesson> academyLessonsOfLevel(int level) =>
    kAcademyLessons.where((l) => l.level == level).toList();

// ── السيناريوهات العملية (8) ──
//
// عنوان المهمة + الدرس المرتبط + الأداة العاملة التي تُنفَّذ فيها.
// «task» تعليمات استخدام للأداة داخل التطبيق (أنشئ خطة، وزّع الضيوف…)
// لا نص حالة دراسية منسوب للكتاب؛ نص الحالة نفسه قيد الإعداد.

class AcademyScenario {
  final String id, title, lessonId, task;
  final AcademyTool tool;
  const AcademyScenario(
      this.id, this.title, this.lessonId, this.tool, this.task);
}

const List<AcademyScenario> kAcademyScenarios = [
  AcademyScenario('S1', 'ترتيب جلوس مأدبة رسمية', 'L3-02', AcademyTool.seating,
      'أنشئ خطة جلوس جديدة في أداة ترتيب الجلوس، ووزّع الضيوف على المقاعد، ثم احفظ الخطة.'),
  AcademyScenario('S2', 'ترتيب جلوس مؤتمر دولي', 'L3-01', AcademyTool.seating,
      'أنشئ مخطط جلوس لقاعة مؤتمر في أداة ترتيب الجلوس، ووزّع الوفود على المقاعد، ثم احفظ الخطة.'),
  AcademyScenario('S3', 'إعداد برنامج زيارة رسمية', 'L2-10', AcademyTool.events,
      'أنشئ مناسبة من نوع «زيارة رسمية» في أداة تنظيم المناسبات، وأضف فقرات برنامجها الزمني وضيوفها.'),
  AcademyScenario('S4', 'خطة استقبال كبير شخصيات', 'L2-11', AcademyTool.events,
      'أنشئ مناسبة استقبال في أداة تنظيم المناسبات، وأضف قائمة تحقق لمراحل الاستقبال.'),
  AcademyScenario('S5', 'خطة توديع كبير شخصيات', 'L2-13', AcademyTool.events,
      'أنشئ مناسبة توديع في أداة تنظيم المناسبات، وأضف فقرات برنامج التوديع وضيوفه.'),
  AcademyScenario(
      'S6',
      'ترتيب أسبقية وفد رسمي',
      'L2-02',
      AcademyTool.precedence,
      'أدخل أسماء الوفد ومناصبهم في أداة الأسبقية الرسمية، وراجع الترتيب المقترح.'),
  AcademyScenario('S7', 'تنظيم مؤتمر دولي', 'L3-01', AcademyTool.events,
      'أنشئ مناسبة من نوع «مؤتمر» في أداة تنظيم المناسبات، وأضف جدول أعمالها وقائمة ضيوفها.'),
  AcademyScenario(
      'S8',
      'إعداد وثيقة مراسم: تقديم أوراق اعتماد',
      'L3-06',
      AcademyTool.docs,
      'افتح مولّد المستندات واختر القالب الأقرب، واملأ حقوله، ثم صدّر المستند.'),
];

// ── تقييم المستوى (محسوب من سجل التقدم فقط) ──

class AcademyAssessment {
  final int recommendedLevel; // 0 = كل المستويات مكتملة
  final String message;
  const AcademyAssessment(this.recommendedLevel, this.message);
}

AcademyAssessment assessAcademyLevel(
    Map<int, int> completedPerLevel, Map<int, int> totalPerLevel) {
  for (var level = 1; level <= 3; level++) {
    final done = completedPerLevel[level] ?? 0;
    final total = totalPerLevel[level] ?? 0;
    if (total > 0 && done < total) {
      return AcademyAssessment(level,
          'أكملت $done من $total دروس المستوى $level. المستوى المقترح لك الآن: المستوى $level.');
    }
  }
  return const AcademyAssessment(0,
      'أكملت دروس المستويات الثلاثة كلها. راجع اختباراتك أو أعد الدروس لتثبيت المعرفة.');
}

class AcademyProgressSummary {
  final int totalLessons, completedLessons, totalAttempts;
  final Map<int, int> completedPerLevel, totalPerLevel;
  const AcademyProgressSummary(this.totalLessons, this.completedLessons,
      this.totalAttempts, this.completedPerLevel, this.totalPerLevel);

  factory AcademyProgressSummary.from(List<AcademyProgress> rows) {
    final byId = {for (final r in rows) r.lessonId: r};
    final completedPerLevel = <int, int>{1: 0, 2: 0, 3: 0};
    final totalPerLevel = <int, int>{1: 0, 2: 0, 3: 0};
    var completed = 0;
    var attempts = 0;
    for (final l in kAcademyLessons) {
      totalPerLevel[l.level] = (totalPerLevel[l.level] ?? 0) + 1;
      final p = byId[l.id];
      if (p == null) continue;
      attempts += p.attempts;
      if (p.completed) {
        completed++;
        completedPerLevel[l.level] = (completedPerLevel[l.level] ?? 0) + 1;
      }
    }
    return AcademyProgressSummary(kAcademyLessons.length, completed, attempts,
        completedPerLevel, totalPerLevel);
  }

  AcademyAssessment get assessment =>
      assessAcademyLevel(completedPerLevel, totalPerLevel);
}

// ── أدوات مساعدة ──

List<String> _jsonStringList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

Widget _pendingChip() => const Chip(
      label: Text(kAcademyLessonPendingLabel),
      backgroundColor: AppColors.silverLight,
    );

Widget _reviewChip() => const Chip(
      label: Text(kAcademyQuizReviewStatus),
      backgroundColor: AppColors.silverLight,
    );

String _shortDate(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

void _showScenarioSheet(BuildContext context, AcademyScenario s) {
  final lesson = academyLessonById(s.lessonId);
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _pendingChip(),
            const SizedBox(height: 8),
            Text('الدرس المرتبط: ${lesson?.title ?? s.lessonId}'),
            const SizedBox(height: 4),
            Text(s.task, style: const TextStyle(height: 1.8)),
            const SizedBox(height: 4),
            const Text(
                'نص الحالة الدراسية الكامل قيد الإعداد — بانتظار المراجعة البشرية، ولا يُعرض هنا أي نص منسوب إلى الكتاب.',
                style: TextStyle(height: 1.8)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => s.tool.page()));
                    },
                    child: Text('فتح ${s.tool.labelAr}'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ── الصفحة الرئيسية للأكاديمية ──

class AcademyPage extends StatefulWidget {
  const AcademyPage({super.key});
  @override
  State<AcademyPage> createState() => _AcademyPageState();
}

class _AcademyPageState extends State<AcademyPage> {
  AcademyProgressSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ensureAcademyTables();
    final rows = await allAcademyProgress();
    if (!mounted) return;
    setState(() {
      _summary = AcademyProgressSummary.from(rows);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(title: Text(trc(context, 'academy_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trc(context, 'academy_intro'),
                        style: const TextStyle(height: 1.8, fontSize: 15)),
                    const SizedBox(height: 12),
                    // تقييم المستوى — محسوب من سجل التقدم المحلي فقط.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.assessment, color: AppColors.gold),
                              SizedBox(width: 8),
                              Text('تقييم المستوى',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              summary == null
                                  ? 'لا بيانات تقدم بعد — ابدأ أول درس ليظهر تقييم مستواك هنا.'
                                  : summary.assessment.message,
                              style: const TextStyle(height: 1.8),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.bar_chart, size: 18),
                              label: const Text('عرض سجل التقدم'),
                              onPressed: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const ProgressPage()));
                                _load();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final level in kAcademyLevels) ...[
                      SectionHeader(title: level.titleAr),
                      Text(level.subAr,
                          style: TextStyle(color: context.mutedColor)),
                      const SizedBox(height: 6),
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.navy,
                            child: Text('${level.id}',
                                style: const TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: Text(
                              'الدروس: ${academyLessonsOfLevel(level.id).length} دروس'),
                          subtitle: summary == null
                              ? null
                              : LinearProgressIndicator(
                                  value: (summary.totalPerLevel[level.id] ??
                                              0) >
                                          0
                                      ? (summary.completedPerLevel[level.id] ??
                                              0) /
                                          (summary.totalPerLevel[level.id] ?? 1)
                                      : 0,
                                ),
                          trailing: const Icon(Icons.arrow_back_ios, size: 14),
                          onTap: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => LessonsPage(level: level)));
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.quiz_outlined,
                              color: AppColors.gold),
                          title: const Text('اختبار المستوى'),
                          subtitle: Text(
                              'أسئلة اختيار من متعدد لدروس المستوى ${level.id} — كلها $kAcademyQuizReviewStatus.'),
                          trailing: const Icon(Icons.arrow_back_ios, size: 14),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => QuizPage(level: level.id))),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SectionHeader(title: trc(context, 'academy_quiz_title')),
                    const SizedBox(height: 6),
                    ...kAcademyScenarios.map((s) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: const Icon(Icons.cases_outlined,
                                color: AppColors.navy),
                            title: Text(s.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${academyLessonById(s.lessonId)?.title ?? ''} • ${s.tool.labelAr}'),
                            trailing:
                                const Icon(Icons.arrow_back_ios, size: 14),
                            onTap: () => _showScenarioSheet(context, s),
                          ),
                        )),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── دروس مستوى واحد ──

class LessonsPage extends StatefulWidget {
  final AcademyLevel level;
  const LessonsPage({super.key, required this.level});
  @override
  State<LessonsPage> createState() => _LessonsPageState();
}

class _LessonsPageState extends State<LessonsPage> {
  Map<String, AcademyProgress> _progress = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await allAcademyProgress();
    if (!mounted) return;
    setState(() {
      _progress = {for (final r in rows) r.lessonId: r};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lessons = academyLessonsOfLevel(widget.level.id);
    return Scaffold(
      appBar: AppBar(title: Text(widget.level.titleAr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(widget.level.subAr,
                    style: TextStyle(color: context.mutedColor)),
                const SizedBox(height: 8),
                ...lessons.map((lesson) {
                  final p = _progress[lesson.id];
                  final done = p?.completed ?? false;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Icon(
                          done ? Icons.check_circle : Icons.play_circle_outline,
                          color: done ? Colors.green : AppColors.navy),
                      title: Text(lesson.title,
                          style: const TextStyle(fontSize: 14.5)),
                      subtitle: Text(
                          'الموضوع ${lesson.topicId} في قاعدة المعرفة • $kAcademyLessonPendingLabel'
                          '${p != null && p.attempts > 0 ? ' • اختبار: أفضل نتيجة ${p.bestScore}/${p.quizTotal} (${p.attempts} محاولات)' : ''}'),
                      trailing: const Icon(Icons.arrow_back_ios, size: 14),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => LessonPage(lesson: lesson)));
                        _load();
                      },
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

// ── صفحة الدرس ──

class LessonPage extends StatefulWidget {
  final AcademyLesson lesson;
  const LessonPage({super.key, required this.lesson});
  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  KbTopic? _topic;
  List<KbTopic> _supporting = [];
  AcademyProgress? _progress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final topic = await Repo.i.topicById(widget.lesson.topicId);
    final supporting = <KbTopic>[];
    for (final id in widget.lesson.supportingTopicIds) {
      final t = await Repo.i.topicById(id);
      if (t != null) supporting.add(t);
    }
    final progress = await lessonProgress(widget.lesson.id);
    if (!mounted) return;
    setState(() {
      _topic = topic;
      _supporting = supporting;
      _progress = progress;
      _loading = false;
    });
  }

  Future<void> _markComplete() async {
    await markLessonComplete(widget.lesson.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تمييز الدرس كمكتمل في سجل التقدم.')));
    }
  }

  Widget _kbSection(String title, String? text) {
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(height: 1.9, fontSize: 14.5)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _kbListSection(String title, String? rawJson) {
    final items = _jsonStringList(rawJson);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: 4),
        ...items.map((it) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                      child: Text(it,
                          style: const TextStyle(height: 1.9, fontSize: 14.5))),
                ],
              ),
            )),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final topic = _topic;
    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : topic == null
              ? EmptyState(
                  icon: Icons.menu_book,
                  text:
                      'موضوع قاعدة المعرفة ${lesson.topicId} غير موجود في هذه النسخة من قاعدة البيانات.',
                  onRetry: _load,
                  retryLabel: 'إعادة المحاولة')
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // جسم الدرس التعليمي — لا نص هنا إطلاقاً، الوسم حرفياً.
                      Card(
                        color: AppColors.silverLight,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _pendingChip(),
                              const SizedBox(height: 8),
                              const Text(
                                  'جسم هذا الدرس التعليمي قيد الإعداد — بانتظار المراجعة البشرية. لا يُعرض هنا أي نص تعليمي منسوب إلى الكتاب قبل تلك المراجعة. ما يلي هو موضوع قاعدة المعرفة المرتبط بالدرس كما هو مسجَّل فيها، مع حالة نصه.',
                                  style: TextStyle(height: 1.9)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const SectionHeader(title: 'موضوع قاعدة المعرفة المرتبط'),
                      const SizedBox(height: 6),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(topic.title,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('${topic.part} — ${topic.chapter}',
                                  style: TextStyle(color: context.mutedColor)),
                              Text(
                                  'المصدر: كتاب «البروتوكول والمراسم» — الموضوع ${topic.id}'
                                  '${topic.bookPagesLabel.isNotEmpty ? '، ${topic.bookPagesLabel}' : ''}',
                                  style: TextStyle(color: context.mutedColor)),
                              const SizedBox(height: 4),
                              Text(
                                  'حالة نص قاعدة المعرفة: ${topic.textStatus.isEmpty ? 'غير مسجلة' : topic.textStatus} — لم تُراجَع بشرياً.',
                                  style: TextStyle(color: context.mutedColor)),
                              if (_progress != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                    'التقدم: ${_progress!.completed ? 'مكتمل' : 'غير مكتمل'}'
                                    '${_progress!.attempts > 0 ? ' • اختبار: أفضل نتيجة ${_progress!.bestScore}/${_progress!.quizTotal} (${_progress!.attempts} محاولات)' : ''}'),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // حقول قاعدة المعرفة نفسها — ما ورد فقط، موسوماً بمصدره.
                      _kbSection(
                          'التعريف — من قاعدة المعرفة', topic.definition),
                      _kbSection('الشرح — من قاعدة المعرفة', topic.explanation),
                      _kbListSection('القواعد والمبادئ — من قاعدة المعرفة',
                          topic.rulesJson),
                      _kbListSection('الإجراءات العملية — من قاعدة المعرفة',
                          topic.proceduresJson),
                      _kbListSection('أمثلة — من قاعدة المعرفة حيثما وردت',
                          topic.examplesJson),
                      _kbListSection(
                          'أخطاء شائعة — من قاعدة المعرفة حيثما وردت',
                          topic.mistakesJson),
                      _kbListSection('نقاط أساسية — من قاعدة المعرفة',
                          topic.keyPointsJson),
                      if (_supporting.isNotEmpty) ...[
                        const SectionHeader(title: 'مواضيع داعمة من قاعدة المعرفة'),
                        const SizedBox(height: 4),
                        ..._supporting.map((t) => Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                leading: const Icon(Icons.link,
                                    color: AppColors.navy),
                                title: Text(t.title),
                                subtitle: Text(
                                    '${t.part} — ${t.chapter}${t.bookPagesLabel.isNotEmpty ? ' • ${t.bookPagesLabel}' : ''}'),
                              ),
                            )),
                        const SizedBox(height: 12),
                      ],
                      // أزرار وظيفية فقط.
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.quiz_outlined),
                          label: const Text('ابدأ اختبار الدرس'),
                          onPressed: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => QuizPage(lesson: lesson)));
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (lesson.tool != AcademyTool.none)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.build),
                            label: Text('فتح ${lesson.tool.labelAr}'),
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => lesson.tool.page())),
                          ),
                        ),
                      if (lesson.tool != AcademyTool.none)
                        const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon((_progress?.completed ?? false)
                              ? Icons.check_circle
                              : Icons.check_circle_outline),
                          label: Text((_progress?.completed ?? false)
                              ? 'الدرس مكتمل في سجل التقدم'
                              : 'تمييز الدرس كمكتمل'),
                          onPressed: (_progress?.completed ?? false)
                              ? null
                              : _markComplete,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.menu_book),
                          label: const Text('تصفح موضوعات ذات صلة في الموسوعة'),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ProtocolGuidePage())),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ── صفحة الاختبار (درس واحد أو مستوى كامل) ──

class QuizPage extends StatefulWidget {
  final AcademyLesson? lesson;
  final int? level;
  const QuizPage({super.key, this.lesson, this.level})
      : assert(lesson != null || level != null,
            'QuizPage needs a lesson or a level');
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  List<QuizQuestion> _questions = [];
  List<AcademyLesson> _lessons = [];
  int _index = 0;
  int _selected = -1;
  bool _checked = false;
  int _score = 0;
  bool _finished = false;
  bool _loading = true;
  String? _explanation;

  String get _title {
    if (widget.lesson != null) return 'اختبار: ${widget.lesson!.title}';
    return 'اختبار المستوى ${widget.level}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ensureAcademyTables();
    final lessons = widget.lesson != null
        ? [widget.lesson!]
        : academyLessonsOfLevel(widget.level!);
    final questions = <QuizQuestion>[];
    for (final l in lessons) {
      questions.addAll(await quizQuestionsForLesson(l.id));
    }
    if (!mounted) return;
    setState(() {
      _lessons = lessons;
      _questions = questions;
      _loading = false;
    });
  }

  Future<void> _check() async {
    final q = _questions[_index];
    final db = await Repo.i.db;
    final explanation = await quizExplanationFor(db, q);
    setState(() {
      _checked = true;
      _explanation = explanation;
      if (_selected == q.correctIndex) _score++;
    });
  }

  Future<void> _next() async {
    if (_index + 1 >= _questions.length) {
      // حفظ المحاولة لكل درس مشمول (نتيجة الدرس الواحد تُحفظ كاملة؛
      // وفي اختبار المستوى تُحفظ نتيجة كل درس على حدة).
      for (final l in _lessons) {
        final qs = _questions.where((q) => q.lessonId == l.id).toList();
        if (qs.isEmpty) continue;
        var s = 0;
        for (var i = 0; i < _questions.length; i++) {
          // النتيجة تُحتسب من الإجابات الصحيحة المسجلة أثناء التقدم؛
          // نعيد حسابها هنا من الخيارات المختارة المحفوظة في _answers.
          if (_answers[_questions[i].id] == _questions[i].correctIndex) {
            if (_questions[i].lessonId == l.id) s++;
          }
        }
        await recordQuizAttempt(l.id, s, qs.length);
      }
      setState(() => _finished = true);
    } else {
      setState(() {
        _index++;
        _selected = -1;
        _checked = false;
        _explanation = null;
      });
    }
  }

  // إجابات المستخدم حسب معرّف السؤال (تُملأ عند كل تصحيح).
  final Map<int, int> _answers = {};

  void _recordAnswer(QuizQuestion q) {
    _answers[q.id] = _selected;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _finished
              ? _resultView()
              : _questions.isEmpty
                  ? const EmptyState(
                      icon: Icons.quiz_outlined,
                      text:
                          'لا توجد أسئلة لهذا الدرس بعد. بنك الأسئلة قيد المراجعة البشرية، ولا يُعرض سؤال بلا مصدر موثق في قاعدة المعرفة.')
                  : _questionView(),
    );
  }

  Widget _questionView() {
    final q = _questions[_index];
    final lesson = academyLessonById(q.lessonId);
    final correct = _checked && _selected == q.correctIndex;
    final wrong = _checked && _selected != q.correctIndex;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('السؤال ${_index + 1} من ${_questions.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              _reviewChip(),
            ],
          ),
          const SizedBox(height: 8),
          if (lesson != null)
            Text('الدرس: ${lesson.title}',
                style: TextStyle(color: context.mutedColor)),
          const SizedBox(height: 8),
          Text(q.question,
              style: const TextStyle(
                  fontSize: 16, height: 1.9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          RadioGroup<int>(
            groupValue: _selected,
            onChanged: (v) {
              if (_checked) return;
              setState(() => _selected = v ?? -1);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(q.options.length, (i) {
                  final isCorrectOption = _checked && i == q.correctIndex;
                  final isWrongPick = _checked && i == _selected && wrong;
                  return Card(
                    color: isCorrectOption
                        ? Colors.green.withValues(alpha: 0.12)
                        : isWrongPick
                            ? Colors.red.withValues(alpha: 0.10)
                            : null,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: RadioListTile<int>(
                      value: i,
                      title: Text(q.options[i],
                          style: const TextStyle(height: 1.7)),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_checked) ...[
            Card(
              color: correct
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.red.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(correct ? 'إجابة صحيحة.' : 'إجابة غير صحيحة.',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('الإجابة الصحيحة: ${q.options[q.correctIndex]}',
                        style: const TextStyle(height: 1.8)),
                    const SizedBox(height: 4),
                    Text(_explanation ?? '',
                        style: const TextStyle(height: 1.8)),
                    Text(
                        'المصدر: الموضوع ${q.topicId}، ص. ${q.sourcePage} من الكتاب.',
                        style: TextStyle(color: context.mutedColor)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _checked
                  ? _next
                  : (_selected < 0
                      ? null
                      : () {
                          _recordAnswer(q);
                          _check();
                        }),
              child: Text(_checked
                  ? (_index + 1 >= _questions.length
                      ? 'عرض النتيجة'
                      : 'السؤال التالي')
                  : 'تحقق من الإجابة'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.emoji_events, color: AppColors.gold),
                    SizedBox(width: 8),
                    Text('نتيجة الاختبار',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  Text('نتيجتك: $_score من ${_questions.length}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                      'حُفظت هذه المحاولة في سجل التقدم. بنك الأسئلة قيد المراجعة البشرية، والشرح المرجعي لكل إجابة موضع المبحث وصفحاته في قاعدة المعرفة.',
                      style: TextStyle(height: 1.8)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _index = 0;
                  _selected = -1;
                  _checked = false;
                  _score = 0;
                  _finished = false;
                  _explanation = null;
                  _answers.clear();
                });
              },
              child: const Text('إعادة الاختبار'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('العودة'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── سجل التقدم ──

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  AcademyProgressSummary? _summary;
  Map<String, AcademyProgress> _byId = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await allAcademyProgress();
    if (!mounted) return;
    setState(() {
      _summary = AcademyProgressSummary.from(rows);
      _byId = {for (final r in rows) r.lessonId: r};
      _loading = false;
    });
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تعيين سجل التقدم؟'),
        content: const Text(
            'سيُمسح سجل إكمال الدروس ونتائج الاختبارات والمحاولات نهائياً. بنك الأسئلة لا يُمس.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('مسح السجل')),
        ],
      ),
    );
    if (ok != true) return;
    await resetAcademyProgress();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم مسح سجل تقدم الأكاديمية.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('سجل تقدم الأكاديمية')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.bar_chart, color: AppColors.gold),
                            SizedBox(width: 8),
                            Text('التقدم العام',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 8),
                          Text(
                              'دروس مكتملة: ${summary?.completedLessons ?? 0} من ${summary?.totalLessons ?? kAcademyLessons.length} • محاولات اختبار: ${summary?.totalAttempts ?? 0}'),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: (summary?.totalLessons ?? 0) > 0
                                ? (summary!.completedLessons /
                                    summary.totalLessons)
                                : 0,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            summary == null ? '' : summary.assessment.message,
                            style: const TextStyle(height: 1.8),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('إعادة تعيين سجل التقدم'),
                            onPressed: _confirmReset,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final level in kAcademyLevels) ...[
                    SectionHeader(title: level.titleAr),
                    const SizedBox(height: 4),
                    Text(
                        'مكتمل: ${summary?.completedPerLevel[level.id] ?? 0} من ${summary?.totalPerLevel[level.id] ?? academyLessonsOfLevel(level.id).length}'),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (summary?.totalPerLevel[level.id] ?? 0) > 0
                          ? (summary!.completedPerLevel[level.id] ?? 0) /
                              (summary.totalPerLevel[level.id] ?? 1)
                          : 0,
                    ),
                    const SizedBox(height: 6),
                    ...academyLessonsOfLevel(level.id).map((lesson) {
                      final p = _byId[lesson.id];
                      final done = p?.completed ?? false;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: Icon(
                              done
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: done ? Colors.green : AppColors.stone),
                          title: Text(lesson.title,
                              style: const TextStyle(fontSize: 14.5)),
                          subtitle: Text(p == null
                              ? 'لم يبدأ بعد'
                              : 'آخر تحديث: ${_shortDate(p.updatedAt)}'
                                  '${p.attempts > 0 ? ' • اختبار: أفضل نتيجة ${p.bestScore}/${p.quizTotal} (${p.attempts} محاولات)' : ''}'),
                          onTap: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        LessonPage(lesson: lesson)));
                            _load();
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
    );
  }
}
