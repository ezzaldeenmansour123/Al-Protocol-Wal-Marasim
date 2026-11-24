// طبقة خدمة الاسترجاع: تربط نواة الاسترجاع الخالصة (retrieval_core)
// بقاعدة البيانات المحلية عبر Repo (sqflite).
//
// خط الأنابيب لكل سؤال:
//   1. مصطلحات السؤال من النواة (تطبيع + كلمات توقف).
//   2. بحث FTS5 في kb_topics_fts (حتى 10 مقاطع) بالمراحل الثلاث
//      (AND ثم OR ثم أطول مصطلح).
//   3. المقالات الـ49 (articles_fts) احتياطي ثانوي فقط: تُبحث عندما
//      تكون مواضيع الكتاب غائبة (قاعدة قديمة v1) أو أقل من الحد.
//   4. دمج بترتيب الصلة (R1): مطابقة العنوان أولاً (عدد مصطلحات
//      السؤال المميزة في العنوان + مفردات الفهرس الإنجليزية
//      والعربية)، ثم رتبة FTS5، ثم مواضيع الكتاب قبل المقالات عند
//      التساوي، ثم المصدر المتحقق (الكتاب) قبل غيره.
//   5. عدّ المصطلحات المطابقة ومطابقة العنوان في كل مقطع، ثم قرار
//      الرفض من حارس منع الاختلاق (نطاق مواد فيينا 1–53 وعتبة
//      الصلة) ثم من النواة.
//
// ملاحظتان:
// - رتبتا FTS5 من جدولين مختلفين ليستا قابلتين للمقارنة الدقيقة
//   عددياً؛ الدمج هنا تقريبي وموثق، وتقيسه مجموعة الـ100 سؤال (P4).
// - لا شبكة ولا مفاتيح ولا توليد في هذه الطبقة إطلاقاً.

import '../db.dart';
import 'refusal_guard.dart' as guard;
import 'retrieval_core.dart' as core;

/// خدمة الاسترجاع المحلي (R بلا G) فوق قاعدة المعرفة.
class RetrievalService {
  final Repo repo;

  RetrievalService({Repo? repo}) : repo = repo ?? Repo.i;

  /// هل طبقة الاسترجاع جاهزة؟ (مواضيع كتاب أو مقالات موجودة).
  Future<bool> get isReady async {
    try {
      if (await repo.kbTopicCount() > 0) return true;
      final latest = await repo.latestArticles(limit: 1);
      return latest.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// هل جدول مواضيع الكتاب موجود؟ false في قواعد v1 القديمة.
  Future<bool> get kbAvailable async {
    try {
      final db = await repo.db;
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM sqlite_master "
        "WHERE type = 'table' AND name = 'kb_topics'",
      );
      return (rows.first['c'] as int) > 0;
    } catch (_) {
      return false;
    }
  }

  /// يسترجع حتى [limit] مقطعاً للسؤال، مع قرار الرفض.
  ///
  /// الترتيب (R1 — مطابق للعدّاد tools/run_baseline.py): يُجلب حتى
  /// [core.ftsFetchLimit] مرشحاً من كل مرحلة FTS5، ثم يُعاد ترتيبهم
  /// بمطابقة العنوان أولاً (عدد مصطلحات السؤال المميزة في العنوان +
  /// مفردات الفهرس)، ثم رتبة FTS5، ثم الكتاب قبل المقالات، ثم المصدر
  /// المتحقق. بعد الدمج يقرر حارس منع الاختلاق الرفض (نطاق مواد
  /// فيينا 1–53، وعتبة الصلة) قبل قرار النواة.
  Future<core.RetrievalResult> retrieve(String query, {int limit = 10}) async {
    final terms = core.queryTerms(query);
    final kbOk = await kbAvailable;
    if (terms.isEmpty) {
      return core.evaluateRetrieval(
        const [],
        queryTermCount: 0,
        kbAvailable: kbOk,
      );
    }
    final kbChunks =
        kbOk ? await _searchKb(query, limit) : const <core.RetrievedChunk>[];
    // المقالات احتياطي ثانوي: تُبحث فقط عند غياب مواضيع الكتاب أو
    // قلّتها عن الحد، حتى لا تُخفّف نتائج الكتاب.
    final articleChunks = (kbChunks.length < limit)
        ? await _searchArticles(query, limit)
        : const <core.RetrievedChunk>[];
    final merged = _merge(kbChunks, articleChunks, terms, limit);
    final refusal = guard.decideRefusal(
      query: query,
      chunks: merged,
      queryTermCount: terms.length,
    );
    if (refusal.refused) {
      return core.RetrievalResult(
        chunks: merged,
        refused: true,
        reason: refusal.reason,
        kbAvailable: kbOk,
      );
    }
    return core.evaluateRetrieval(
      merged,
      queryTermCount: terms.length,
      kbAvailable: kbOk,
    );
  }

  // ── بحث مواضيع الكتاب (FTS5، المراحل الثلاث) ──
  // R1: تُجلب حتى ftsFetchLimit (20) مرشحاً من المرحلة التي تُنتج
  // نتائج، لا 10 فقط، حتى يستطيع ترجيح العنوان في _merge إنقاذ
  // مواضيع صحيحة رتبتها bm25 ضعيفة (مصطلحات شائعة برتبة ≈ 0).
  Future<List<core.RetrievedChunk>> _searchKb(String query, int limit) async {
    final db = await repo.db;
    for (final expr in core.ftsMatchStages(query)) {
      List<Map<String, Object?>> rows;
      try {
        rows = await db.rawQuery(
          'SELECT t.*, f.rank AS _rank FROM kb_topics t '
          'JOIN kb_topics_fts f ON f.rowid = t.rowid '
          'WHERE kb_topics_fts MATCH ? ORDER BY rank LIMIT ?',
          [expr, core.ftsFetchLimit],
        );
      } catch (_) {
        return [];
      }
      if (rows.isNotEmpty) {
        return rows.map(_kbChunkFromMap).toList();
      }
    }
    return [];
  }

  core.RetrievedChunk _kbChunkFromMap(Map<String, Object?> m) {
    final excerpt = core.buildExcerpt(
      definition: m['definition'] as String?,
      explanation: m['explanation'] as String?,
      summary: m['summary'] as String?,
    );
    final rank = (m['_rank'] as num?)?.toDouble() ?? 0;
    return core.RetrievedChunk(
      topicId: m['id'] as String,
      origin: core.ChunkOrigin.kb,
      title: (m['title'] ?? '') as String,
      part: (m['part'] ?? '') as String,
      chapter: (m['chapter'] ?? '') as String,
      mabhas: (m['mabhas'] ?? '') as String,
      excerpt: excerpt,
      bookPageStart: m['book_page_start'] as int?,
      bookPageEnd: m['book_page_end'] as int?,
      bookPageLabel: m['book_page_label'] as String?,
      source: (m['source'] ?? '') as String,
      sourceType: (m['source_type'] ?? 'كتاب') as String,
      textStatus: (m['text_status'] ?? '') as String,
      rankScore: rank,
      // مفردات الفهرس للترتيب فقط (R1) — لا تُعرض كمحتوى. قواعد v1
      // بلا العمودين تعيد null فيُعامل كسلسلة فارغة.
      enKeywords: (m['en_keywords'] ?? '') as String,
      arKeywords: (m['ar_keywords'] ?? '') as String,
    );
  }

  // ── بحث المقالات الاحتياطي (FTS5، المراحل الثلاث) ──
  Future<List<core.RetrievedChunk>> _searchArticles(
      String query, int limit) async {
    final db = await repo.db;
    for (final expr in core.ftsMatchStages(query)) {
      List<Map<String, Object?>> rows;
      try {
        rows = await db.rawQuery(
          'SELECT a.*, f.rank AS _rank FROM articles a '
          'JOIN articles_fts f ON f.rowid = a.id '
          'WHERE articles_fts MATCH ? ORDER BY rank LIMIT ?',
          [expr, limit],
        );
      } catch (_) {
        return [];
      }
      if (rows.isNotEmpty) {
        return rows.map(_articleChunkFromMap).toList();
      }
    }
    return [];
  }

  core.RetrievedChunk _articleChunkFromMap(Map<String, Object?> m) {
    final id = m['id'] as int;
    final sourceName = (m['source_name'] ?? '') as String;
    final sourceOrg = (m['source_org'] ?? '') as String;
    final sourceUrl = (m['source_url'] ?? '') as String;
    final source = sourceOrg.isEmpty ? sourceName : '$sourceName — $sourceOrg';
    final rank = (m['_rank'] as num?)?.toDouble() ?? 0;
    return core.RetrievedChunk(
      topicId: 'article-$id',
      articleId: id,
      origin: core.ChunkOrigin.article,
      title: (m['title'] ?? '') as String,
      part: '',
      chapter: (m['section'] ?? '') as String,
      excerpt: core.buildExcerpt(summary: m['body'] as String?),
      source: source,
      // المقالات محتوى مراسيم المنسَّق؛ ليست مادة كتاب ولا مرجعاً
      // خارجياً متحققاً بالضرورة — تُوسم كمقال لا ككتاب.
      sourceType: sourceUrl.isNotEmpty ? 'مرجع خارجي' : 'مقال',
      textStatus: '',
      rankScore: rank,
    );
  }

  // ── الدمج والترتيب ──
  // R1 — الصيغة المثبتة (F1 في تجربة القياس): مطابقة العنوان أولاً
  // (عدد مصطلحات السؤال المميزة في العنوان + مفردات الفهرس)، ثم
  // رتبة FTS5 (الأكثر سلبية = الأعلى صلة)، ثم مواضيع الكتاب قبل
  // المقالات عند التساوي، ثم المصدر المتحقق. مطابقة تماماً لإعادة
  // الترتيب في tools/run_baseline.py.
  List<core.RetrievedChunk> _merge(
    List<core.RetrievedChunk> kb,
    List<core.RetrievedChunk> articles,
    List<String> terms,
    int limit,
  ) {
    final all = [...kb, ...articles];
    int originRank(core.RetrievedChunk c) =>
        c.origin == core.ChunkOrigin.kb ? 0 : 1;
    int verifiedRank(core.RetrievedChunk c) => c.sourceType == 'كتاب' ? 0 : 1;
    final scored = all
        .map((c) => c.copyWith(
              matchedTerms:
                  core.countMatchedTerms('${c.title} ${c.excerpt}', terms),
              titleMatches: core.countTitleMatchedTerms(
                c.title,
                terms,
                enKeywords: c.enKeywords,
                arKeywords: c.arKeywords,
              ),
            ))
        .toList();
    scored.sort((a, b) {
      final byTitle = b.titleMatches.compareTo(a.titleMatches);
      if (byTitle != 0) return byTitle;
      final byRank = a.rankScore.compareTo(b.rankScore);
      if (byRank != 0) return byRank;
      final byOrigin = originRank(a).compareTo(originRank(b));
      if (byOrigin != 0) return byOrigin;
      return verifiedRank(a).compareTo(verifiedRank(b));
    });
    return scored.take(limit).toList();
  }
}
