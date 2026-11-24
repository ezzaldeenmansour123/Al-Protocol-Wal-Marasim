// ── الأكاديمية: مخطط قاعدة البيانات + بنك الأسئلة + سجل التقدم ──
//
// CHARTER_V2 §7 + V2_PLAN §1.4. ملف مخطط منفصل عن lib/db.dart (لا يُعدَّل
// db.dart): يوفّر المنسّق استدعاء createAcademyTables() من _ensureV2Schema
// أو من onCreate عند الربط النهائي. كل الدوال هنا idempotent (آمنة لإعادة
// الاستدعاء): الجداول CREATE IF NOT EXISTS، والبذر لا يعمل إلا على جدول
// أسئلة فارغ.
//
// قاعدة المحتوى الصارمة (ملزمة):
//  1. لا يُؤلَّف أي نص تعليمي منسوب إلى الكتاب. بنك الأسئلة لا يحوي إلا
//     أسئلة بنيوية عن موضع المبحث في الكتاب نفسه (إلى أي باب وفصل ينتمي
//     هذا المبحث؟)، تُبنى نصوصها آلياً من حقول kb_topics (العنوان، الباب،
//     الفصل، الصفحات) وقت البذر، وإجابتها الصحيحة حقلٌ من قاعدة المعرفة.
//  2. كل سؤال يحمل topic_id + رقم صفحة (book_page_start) ويُتحقق منه
//     برمجياً عبر validateQuizBank(): الموضوع موجود، والصفحة داخل
//     [book_page_start, book_page_end]، والخيار الصحيح يطابق
//     "الباب — الفصل" المسجَّل في kb_topics لذلك الموضوع.
//  3. كل بنك الأسئلة موسوم حرفياً «قيد المراجعة البشرية» (عمود status)،
//     ولا يُعرض أي سؤال على أنه مراجَع أو من نص الكتاب.
//  4. الدروس نفسها (عناوينها وروابط topic_id) في lib/academy.dart؛ هذا
//     الملف لا يحوي أي نص درس.
//
// العدّ: 31 درساً = 9 مباحث (الباب الأول) + 14 (الباب الثاني ف1: المبحث
// الأول + جوانب الأسبقية الثمانية + المباحث 3–6 + الملخص البصري للاستقبال
// كمبحث مستقل) + 8 (الباب الثاني ف2–ف3). مقدمة الأسبقية (P2C1-M2-00)
// وتعــارض المعايير (P2C1-M2-09) وخلاصتها (P2C1-M2-10) مواضيع داعمة
// مرتبطة بدروس الأسبقية، لا دروساً مستقلة — انظر lib/academy.dart.
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db.dart';

/// وسم الحالة الإلزامي لكل بنك الأسئلة — حرفياً كما في المهمة.
const String kAcademyQuizReviewStatus = 'قيد المراجعة البشرية';

/// وسم حالة جسم الدرس التعليمي — حرفياً كما في المهمة.
const String kAcademyLessonPendingLabel =
    'قيد الإعداد — بانتظار المراجعة البشرية';

/// الفصول الخمسة للكتاب كما في BOOK_INDEX.md (رموز C1..C5).
/// التسمية: "الباب — الفصل" كما هي مسجَّلة في kb_topics (part/chapter)،
/// ليطابقها التحقق البرمجي حرفياً.
const Map<String, String> kAcademyChapters = {
  'C1': 'الباب الأول — الفصل الأول: ماهية المراسم والبروتوكولات والتشريفات',
  'C2':
      'الباب الأول — الفصل الثاني: التطور التاريخي للمراسم والبروتوكولات عالميًا وعربيًا',
  'C3':
      'الباب الثاني — الفصل الأول: إدارة المراسم والبروتوكول الرسمي في الدولة',
  'C4': 'الباب الثاني — الفصل الثاني: المراسم العملية وإدارة الأحداث الكبرى',
  'C5':
      'الباب الثاني — الفصل الثالث: البروتوكول الدبلوماسي والمناسبات السيادية والدولية',
};

const List<String> kAcademyChapterOrder = ['C1', 'C2', 'C3', 'C4', 'C5'];

/// يبني خيارات سؤال المبحث: الخيار الصحيح + 3 فصول أخرى بالترتيب الدوري،
/// ثم تدوير يساري بمقدار (seedIndex % 4) حتى لا يثبت موضع الإجابة.
/// [correctIndex] المقابل = (4 - seedIndex % 4) % 4.
List<String> buildAcademyQuizOptions(String correctCode, int seedIndex) {
  final correct = kAcademyChapters[correctCode]!;
  final ci = kAcademyChapterOrder.indexOf(correctCode);
  final others = <String>[
    for (var d = 1; d <= 3; d++)
      kAcademyChapters[kAcademyChapterOrder[(ci + d) % 5]]!,
  ];
  final base = <String>[correct, ...others];
  final rot = seedIndex % base.length;
  return [...base.sublist(rot), ...base.sublist(0, rot)];
}

int academyQuizCorrectIndex(int seedIndex) => (4 - seedIndex % 4) % 4;

/// بذرة بنك الأسئلة: سؤال واحد لكل درس من الدروس الـ31.
/// (lessonId, topicId في kb_topics, sourcePage = book_page_start كما في
/// قاعدة المعرفة، رمز الفصل الصحيح). العنوان ونص السؤال والشرح يُبنون وقت
/// البذر من صف kb_topics نفسه — لا نصوص مكتوبة يدوياً هنا.
/// صفحات البداية متحقق منها ضد assets/marasim.db (انظر تقرير التسليم).
const List<(String, String, int, String)> kAcademyQuizSeed = [
  ('L1-01', 'P1C1-M1', 4, 'C1'),
  ('L1-02', 'P1C1-M2', 7, 'C1'),
  ('L1-03', 'P1C1-M3', 9, 'C1'),
  ('L1-04', 'P1C1-M4', 10, 'C1'),
  ('L1-05', 'P1C2-M1', 16, 'C2'),
  ('L1-06', 'P1C2-M2', 22, 'C2'),
  ('L1-07', 'P1C2-M3', 30, 'C2'),
  ('L1-08', 'P1C2-M4', 33, 'C2'),
  ('L1-09', 'P1C2-M5', 37, 'C2'),
  ('L2-01', 'P2C1-M1', 48, 'C3'),
  ('L2-02', 'P2C1-M2-01', 56, 'C3'),
  ('L2-03', 'P2C1-M2-02', 61, 'C3'),
  ('L2-04', 'P2C1-M2-03', 65, 'C3'),
  ('L2-05', 'P2C1-M2-04', 69, 'C3'),
  ('L2-06', 'P2C1-M2-05', 72, 'C3'),
  ('L2-07', 'P2C1-M2-06', 75, 'C3'),
  ('L2-08', 'P2C1-M2-07', 81, 'C3'),
  ('L2-09', 'P2C1-M2-08', 86, 'C3'),
  ('L2-10', 'P2C1-M3', 94, 'C3'),
  ('L2-11', 'P2C1-M4', 99, 'C3'),
  ('L2-12', 'P2C1-M4V', 117, 'C3'),
  ('L2-13', 'P2C1-M5', 126, 'C3'),
  ('L2-14', 'P2C1-M6', 136, 'C3'),
  ('L3-01', 'P2C2-M1', 144, 'C4'),
  ('L3-02', 'P2C2-M2', 158, 'C4'),
  ('L3-03', 'P2C2-M3', 164, 'C4'),
  ('L3-04', 'P2C2-M4', 177, 'C4'),
  ('L3-05', 'P2C3-M1', 192, 'C5'),
  ('L3-06', 'P2C3-M2', 199, 'C5'),
  ('L3-07', 'P2C3-M3', 205, 'C5'),
  ('L3-08', 'P2C3-M4', 211, 'C5'),
];

/// سؤال اختيار من متعدد — صف واحد من جدول quiz_questions.
class QuizQuestion {
  final int id;
  final String lessonId, topicId, question, status;
  final List<String> options;
  final int correctIndex, sourcePage;

  const QuizQuestion(
    this.id,
    this.lessonId,
    this.topicId,
    this.question,
    this.options,
    this.correctIndex,
    this.sourcePage,
    this.status,
  );

  factory QuizQuestion.fromMap(Map<String, Object?> m) {
    final opts = jsonDecode(m['options_json'] as String) as List;
    return QuizQuestion(
      m['id'] as int,
      m['lesson_id'] as String,
      m['topic_id'] as String,
      m['question'] as String,
      opts.map((e) => e as String).toList(),
      m['correct_index'] as int,
      m['source_page'] as int,
      (m['status'] as String?) ?? kAcademyQuizReviewStatus,
    );
  }

  bool get isCorrectlyIndexed =>
      correctIndex >= 0 && correctIndex < options.length;
}

/// صف واحد من سجل التقدم academy_progress (مستخدم محلي، بلا حسابات).
class AcademyProgress {
  final String lessonId;
  final bool completed;
  final int bestScore, quizTotal, attempts;
  final String updatedAt;

  const AcademyProgress(
    this.lessonId,
    this.completed,
    this.bestScore,
    this.quizTotal,
    this.attempts,
    this.updatedAt,
  );

  factory AcademyProgress.fromMap(Map<String, Object?> m) => AcademyProgress(
        m['lesson_id'] as String,
        ((m['completed'] as int?) ?? 0) == 1,
        (m['best_score'] as int?) ?? 0,
        (m['quiz_total'] as int?) ?? 0,
        (m['attempts'] as int?) ?? 0,
        (m['updated_at'] as String?) ?? '',
      );
}

/// ينشئ جداول الأكاديمية إن غابت (آمن لإعادة الاستدعاء).
/// يستدعيها المنسّق من _ensureV2Schema في db.dart أو من onCreate —
/// هذا الملف لا يعدّل db.dart بنفسه.
Future<void> createAcademyTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS quiz_questions (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      lesson_id     TEXT NOT NULL,
      topic_id      TEXT NOT NULL REFERENCES kb_topics(id),
      question      TEXT NOT NULL,
      options_json  TEXT NOT NULL,
      correct_index INTEGER NOT NULL,
      source_page   INTEGER NOT NULL,
      status        TEXT NOT NULL DEFAULT '$kAcademyQuizReviewStatus',
      UNIQUE (lesson_id)
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS academy_progress (
      lesson_id   TEXT PRIMARY KEY,
      completed   INTEGER NOT NULL DEFAULT 0,
      best_score  INTEGER NOT NULL DEFAULT 0,
      quiz_total  INTEGER NOT NULL DEFAULT 0,
      attempts    INTEGER NOT NULL DEFAULT 0,
      updated_at  TEXT NOT NULL
    )''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quiz_topic ON quiz_questions(topic_id)');
}

/// يبذر بنك الأسئلة (31 سؤالاً) إن كان الجدول فارغاً فقط.
/// نص السؤال والشرح يُبنيان من صف kb_topics؛ فإن غاب الموضوع من قاعدة
/// قديمة يُتخطى سؤاله ويُسجَّل في القائمة المعادة (لا يُخترع بديل).
/// يعيد معرّفات الدروس التي لم تُبذر لغياب موضوعها.
Future<List<String>> seedQuizQuestions(DatabaseExecutor db) async {
  final countRows =
      await db.rawQuery('SELECT COUNT(*) AS c FROM quiz_questions');
  if (((countRows.first['c'] as int?) ?? 0) > 0) return const [];
  final skipped = <String>[];
  for (var i = 0; i < kAcademyQuizSeed.length; i++) {
    final (lessonId, topicId, sourcePage, chapterCode) = kAcademyQuizSeed[i];
    final topics = await db.query('kb_topics',
        columns: [
          'title',
          'part',
          'chapter',
          'book_page_start',
          'book_page_end'
        ],
        where: 'id = ?',
        whereArgs: [topicId]);
    if (topics.isEmpty) {
      skipped.add(lessonId);
      continue;
    }
    final t = topics.first;
    final title = (t['title'] as String?) ?? topicId;
    final options = buildAcademyQuizOptions(chapterCode, i);
    await db.insert('quiz_questions', {
      'lesson_id': lessonId,
      'topic_id': topicId,
      'question':
          'إلى أي باب وفصل في كتاب «البروتوكول والمراسم» ينتمي مبحث «$title»؟',
      'options_json': jsonEncode(options),
      'correct_index': academyQuizCorrectIndex(i),
      'source_page': sourcePage,
      'status': kAcademyQuizReviewStatus,
    });
    // الشرح مرجعي لا تعليمي: موضع المبحث + صفحاته كما في قاعدة المعرفة.
    // يُبنى عند العرض من kb_topics عبر quizExplanationFor() حتى لا
    // تتجمد نسخة من نص مرجعي في جدول آخر.
  }
  return skipped;
}

/// شرح مرجعي لإجابة سؤال: موضع المبحث وصفحاته كما في kb_topics.
/// يُبنى عند العرض دائماً من قاعدة المعرفة — لا يُخزَّن نص شرح.
Future<String> quizExplanationFor(DatabaseExecutor db, QuizQuestion q) async {
  final rows = await db.query('kb_topics',
      columns: ['title', 'part', 'chapter', 'book_page_start', 'book_page_end'],
      where: 'id = ?',
      whereArgs: [q.topicId]);
  if (rows.isEmpty) return 'الموضوع ${q.topicId} غير موجود في قاعدة المعرفة.';
  final t = rows.first;
  final start = t['book_page_start'] as int?;
  final end = t['book_page_end'] as int?;
  final pages =
      start != null && end != null ? 'ص. $start–$end' : 'بلا ترقيم مطبوع';
  return 'المبحث «${t['title']}» — ${t['part']}، ${t['chapter']}، '
      '$pages من الكتاب (الموضوع ${q.topicId} في قاعدة المعرفة).';
}

/// يتحقق برمجياً من بنك الأسئلة كاملاً ضد kb_topics.
/// يعيد قائمة أخطاء فارغة عند السلامة؛ أي عنصر فيها يعني أن السؤال
/// المعني لا يجوز عرضه قبل إصلاحه ومراجعته بشرياً.
Future<List<String>> validateQuizBank(DatabaseExecutor db) async {
  final errors = <String>[];
  late final List<Map<String, Object?>> rows;
  try {
    rows = await db.query('quiz_questions', orderBy: 'id');
  } catch (e) {
    return ['تعذّر قراءة جدول quiz_questions: $e'];
  }
  if (rows.isEmpty) {
    return ['جدول quiz_questions فارغ — لم يُبذر بعد.'];
  }
  for (final row in rows) {
    final q = QuizQuestion.fromMap(row);
    final label = 'سؤال الدرس ${q.lessonId} (topic_id=${q.topicId})';
    if (q.status != kAcademyQuizReviewStatus) {
      errors.add('$label: الحالة ليست «$kAcademyQuizReviewStatus».');
    }
    if (q.options.length != 4) {
      errors.add('$label: عدد الخيارات ${q.options.length} لا 4.');
    }
    if (!q.isCorrectlyIndexed) {
      errors.add('$label: correct_index خارج النطاق.');
      continue;
    }
    final topics = await db.query('kb_topics',
        columns: [
          'title',
          'part',
          'chapter',
          'book_page_start',
          'book_page_end'
        ],
        where: 'id = ?',
        whereArgs: [q.topicId]);
    if (topics.isEmpty) {
      errors.add('$label: الموضوع غير موجود في kb_topics.');
      continue;
    }
    final t = topics.first;
    final start = t['book_page_start'] as int?;
    final end = t['book_page_end'] as int?;
    if (start == null || end == null) {
      errors.add('$label: الموضوع بلا نطاق صفحات في قاعدة المعرفة.');
    } else if (q.sourcePage < start || q.sourcePage > end) {
      errors.add('$label: الصفحة ${q.sourcePage} خارج نطاق المبحث '
          '($start–$end).');
    }
    final expectedChapter = '${t['part']} — ${t['chapter']}';
    if (q.options[q.correctIndex] != expectedChapter) {
      errors.add('$label: الخيار الصحيح لا يطابق فصل المبحث في '
          'قاعدة المعرفة («$expectedChapter»).');
    }
    final title = (t['title'] as String?) ?? '';
    if (title.isNotEmpty && !q.question.contains(title)) {
      errors.add('$label: نص السؤال لا يذكر عنوان المبحث.');
    }
  }
  return errors;
}

// ── واجهة Repo (عبر Repo.i.db — دون تعديل db.dart) ──

/// يضمن وجود جداول الأكاديمية وبذر بنك الأسئلة في قاعدة التطبيق.
/// تُستدعى مرة عند فتح الأكاديمية (idempotent).
Future<List<String>> ensureAcademyTables() async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  return seedQuizQuestions(d);
}

Future<List<QuizQuestion>> quizQuestionsForLesson(String lessonId) async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  final rows = await d.query('quiz_questions',
      where: 'lesson_id = ?', whereArgs: [lessonId], orderBy: 'id');
  return rows.map(QuizQuestion.fromMap).toList();
}

Future<List<QuizQuestion>> allQuizQuestions() async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  final rows = await d.query('quiz_questions', orderBy: 'id');
  return rows.map(QuizQuestion.fromMap).toList();
}

Future<List<String>> validateAcademyQuizBank() async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  return validateQuizBank(d);
}

/// يسجّل محاولة اختبار: attempts +1، ويحفظ أفضل نتيجة.
/// لا يعلّم الدرس مكتملاً تلقائياً — الإكمال بقرار المستخدم الصريح
/// (markLessonComplete) بعد قراءة الدرس.
Future<void> recordQuizAttempt(String lessonId, int score, int total) async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  final now = DateTime.now().toIso8601String();
  final existing = await d
      .query('academy_progress', where: 'lesson_id = ?', whereArgs: [lessonId]);
  if (existing.isEmpty) {
    await d.insert('academy_progress', {
      'lesson_id': lessonId,
      'completed': 0,
      'best_score': score,
      'quiz_total': total,
      'attempts': 1,
      'updated_at': now,
    });
  } else {
    final prev = AcademyProgress.fromMap(existing.first);
    await d.update(
        'academy_progress',
        {
          'best_score': score > prev.bestScore ? score : prev.bestScore,
          'quiz_total': total,
          'attempts': prev.attempts + 1,
          'updated_at': now,
        },
        where: 'lesson_id = ?',
        whereArgs: [lessonId]);
  }
}

/// يعلّم الدرس مكتملاً بقرار المستخدم الصريح بعد قراءة الدرس، دون
/// المساس بنتيجة اختبار سابقة (insert إن غاب السجل، وupdate إن وُجد).
Future<void> markLessonComplete(String lessonId) async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  final now = DateTime.now().toIso8601String();
  final existing = await d
      .query('academy_progress', where: 'lesson_id = ?', whereArgs: [lessonId]);
  if (existing.isEmpty) {
    await d.insert('academy_progress', {
      'lesson_id': lessonId,
      'completed': 1,
      'best_score': 0,
      'quiz_total': 0,
      'attempts': 0,
      'updated_at': now,
    });
  } else {
    await d.update('academy_progress', {'completed': 1, 'updated_at': now},
        where: 'lesson_id = ?', whereArgs: [lessonId]);
  }
}

Future<AcademyProgress?> lessonProgress(String lessonId) async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  final rows = await d
      .query('academy_progress', where: 'lesson_id = ?', whereArgs: [lessonId]);
  if (rows.isEmpty) return null;
  return AcademyProgress.fromMap(rows.first);
}

Future<List<AcademyProgress>> allAcademyProgress() async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  final rows = await d.query('academy_progress', orderBy: 'lesson_id');
  return rows.map(AcademyProgress.fromMap).toList();
}

/// يمسح سجل تقدم الأكاديمية كاملاً (بعد تأكيد المستخدم في الواجهة).
/// بنك الأسئلة لا يُمس — هو محتوى لا بيانات مستخدم.
Future<void> resetAcademyProgress() async {
  final d = await Repo.i.db;
  await createAcademyTables(d);
  await d.delete('academy_progress');
}
