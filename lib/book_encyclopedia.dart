import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'app_state.dart';
import 'db.dart';
import 'widgets.dart';

/// موسوعة الكتاب نفسه: كتاب «البروتوكول والمراسم: الأسس النظرية
/// والتطبيقات العملية» لأسعد محمد منصور، ببنية الكتاب كما في جدول
/// kb_topics (أجزاء ← فصول ← مباحث ← نص الموضوع كاملاً مع رقم صفحة
/// الكتاب). تقرأ من جدول kb_topics الموجود في قاعدة الأصول، بلا قاعدة
/// إضافية وبلا أي نص مخترع: كل ما يُعرض حقل من القاعدة، وأي حقل فارغ
/// يعني أن العنصر لم يرد في نص المبحث لا أنه غير موجود أصلاً.
///
/// بنية الـ54 موضوعاً (من knowledge_base.json، متحقق منها في القاعدة):
/// المادة الافتتاحية 1، الباب الأول 14، الباب الثاني 32، الملحقات 4،
/// المراجع 1، الفهرس 1، وخاتمة الكتاب 1 (مسجلة part='—' في القاعدة
/// لأنها خاتمة عامة لا تنتمي إلى باب).
///
/// حالة النص «مصحح آلياً» تعني تصحيحاً آلياً موثقاً لاستخلاص النص، لا
/// مراجعة بشرية — وتُعرض كذلك بأمانة في كل موضع، مع قيد المحتوى
/// للموضوع الجزئي الوحيد (ملخص بصري لمراحل الاستقبال: صور غير مستخرجة).

// ── تجميع بنية الكتاب (دوال خالصة، بلا واجهة) ──

/// جزء من الكتاب (باب / مادة افتتاحية / ملحقات / مراجع / فهرس / خاتمة).
class BookPart {
  const BookPart(this.name, this.topics);
  final String name;
  final List<KbTopic> topics;

  int get count => topics.length;

  String get pagesLabel => _rangeLabel(topics);
}

/// فصل داخل جزء.
class BookChapter {
  const BookChapter(this.name, this.topics);
  final String name;
  final List<KbTopic> topics;

  int get count => topics.length;

  String get pagesLabel => _rangeLabel(topics);
}

/// مبحث (أو قسم) داخل فصل.
class BookMabhas {
  const BookMabhas(this.name, this.topics);
  final String name;
  final List<KbTopic> topics;

  int get count => topics.length;
}

/// أصغر صفحة كتاب في القائمة، أو -1 عند غياب الترقيم المطبوع (المادة
/// الافتتاحية مرقمة بالأحرف) — فتأتي أولاً في ترتيب الكتاب.
int _minBookPage(List<KbTopic> topics) {
  var min = 1 << 30;
  var found = false;
  for (final t in topics) {
    final p = t.bookPageStart;
    if (p != null) {
      found = true;
      if (p < min) min = p;
    }
  }
  return found ? min : -1;
}

/// «ص. X–Y» لنطاق صفحات القائمة، أو '' عند غياب الترقيم.
String _rangeLabel(List<KbTopic> topics) {
  var start = 1 << 30;
  var end = -1;
  var found = false;
  for (final t in topics) {
    final s = t.bookPageStart;
    final e = t.bookPageEnd;
    if (s != null && e != null) {
      found = true;
      if (s < start) start = s;
      if (e > end) end = e;
    }
  }
  if (!found) return '';
  return start == end ? 'ص. $start' : 'ص. $start–$end';
}

/// اسم العرض للجزء: قيمة part كما في القاعدة، إلا '—' فهي خاتمة الكتاب.
String _partDisplayName(String part, List<KbTopic> topics) {
  if (part != '—') return part;
  return topics.isNotEmpty ? topics.first.title : 'خاتمة الكتاب';
}

/// يجمّع المواضيع في أجزاء بترتيب الكتاب (أصغر صفحة أولاً، والمادة
/// الافتتاحية بلا ترقيم أولاً).
List<BookPart> groupBookTopics(List<KbTopic> topics) {
  final byPart = <String, List<KbTopic>>{};
  for (final t in topics) {
    byPart.putIfAbsent(t.part, () => []).add(t);
  }
  final parts = byPart.entries
      .map((e) => BookPart(_partDisplayName(e.key, e.value), e.value))
      .toList();
  parts.sort((a, b) => _minBookPage(a.topics).compareTo(_minBookPage(b.topics)));
  return parts;
}

/// فصول جزء بترتيب الكتاب. الفصل '—' يعني مواضيع بلا فصل (خاتمة باب،
/// مادة افتتاحية، مراجع، فهرس، خاتمة كتاب).
List<BookChapter> chaptersOf(BookPart part) {
  final byChapter = <String, List<KbTopic>>{};
  for (final t in part.topics) {
    byChapter.putIfAbsent(t.chapter, () => []).add(t);
  }
  final list = byChapter.entries
      .map((e) => BookChapter(e.key, e.value))
      .toList();
  list.sort((a, b) => _minBookPage(a.topics).compareTo(_minBookPage(b.topics)));
  return list;
}

/// مباحث فصل بترتيب الكتاب. المبحث '—' يعني مواضيع بلا مبحث.
List<BookMabhas> mabhasOf(List<KbTopic> topics) {
  final byMabhas = <String, List<KbTopic>>{};
  for (final t in topics) {
    byMabhas.putIfAbsent(t.mabhas, () => []).add(t);
  }
  final list =
      byMabhas.entries.map((e) => BookMabhas(e.key, e.value)).toList();
  list.sort((a, b) => _minBookPage(a.topics).compareTo(_minBookPage(b.topics)));
  return list;
}

/// فك ترميز قائمة نصية مخزنة JSON (حقول *_json و subsections في
/// kb_topics)، كما في lib/academy.dart. فشل الفك يعيد [].
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

IconData _partIcon(String name) {
  switch (name) {
    case 'المادة الافتتاحية':
      return Icons.auto_stories;
    case 'الملحقات':
      return Icons.attach_file;
    case 'المراجع':
      return Icons.source;
    case 'الفهرس':
      return Icons.list_alt;
    case 'خاتمة الكتاب':
      return Icons.flag_outlined;
    default:
      return Icons.menu_book;
  }
}

// ── الصفحة الرئيسية لموسوعة الكتاب (جسم بلا Scaffold ليعاد استخدامه
// تبويباً أول في EncyclopediaHubPage وصفحة مستقلة) ──

class BookEncyclopediaView extends StatefulWidget {
  const BookEncyclopediaView({super.key});
  @override
  State<BookEncyclopediaView> createState() => _BookEncyclopediaViewState();
}

class _BookEncyclopediaViewState extends State<BookEncyclopediaView> {
  final _search = TextEditingController();
  List<BookPart> _parts = [];
  List<KbTopic> _searchResults = [];
  bool _loading = true;
  // أي فشل في التحميل (ومنها رمي Repo.i.db) يُعرض كحالة خطأ مع إعادة
  // محاولة — لا مؤشر تحميل أبدي أبداً (علة صفحة الموسوعة على الجهاز).
  bool _loadFailed = false;
  bool _searching = false;
  bool _searchFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final topics = await Repo.i.allKbTopics();
      if (!mounted) return;
      setState(() {
        _parts = groupBookTopics(topics);
        _loading = false;
        // قائمة فارغة = محتوى الكتاب غير متاح في القاعدة المحلية؛
        // تُعرض كحالة فراغ مع إعادة محاولة لا كمؤشر تحميل.
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _onSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _searchResults = [];
        _searchFailed = false;
      });
      return;
    }
    try {
      final res = await Repo.i.searchKbTopics(query);
      if (!mounted) return;
      setState(() {
        _searching = true;
        _searchResults = res;
        _searchFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = true;
        _searchResults = [];
        _searchFailed = true;
      });
    }
  }

  int get _totalCount =>
      _parts.fold(0, (sum, p) => sum + p.count);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'ابحث في مواضيع الكتاب...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _onSearch('');
                      },
                    ),
            ),
            onChanged: _onSearch,
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadFailed
                  ? EmptyState(
                      icon: Icons.error_outline,
                      text: 'تعذّر تحميل مواضيع الكتاب. حاول مرة أخرى.',
                      onRetry: _load,
                      retryLabel: trc(context, 'retry'),
                    )
                  : _searching
                      ? _buildSearchResults(context)
                      : _buildParts(context),
        ),
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    if (_searchFailed) {
      return EmptyState(
        icon: Icons.error_outline,
        text: 'تعذّر البحث في مواضيع الكتاب. حاول مرة أخرى.',
        onRetry: () => _onSearch(_search.text),
        retryLabel: trc(context, 'retry'),
      );
    }
    if (_searchResults.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        text: 'لا توجد مواضيع مطابقة في الكتاب.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) => _topicTile(context, _searchResults[i]),
    );
  }

  Widget _buildParts(BuildContext context) {
    if (_parts.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book,
        text: 'مواضيع الكتاب غير متاحة في قاعدة البيانات المحلية بعد.',
        onRetry: _load,
        retryLabel: trc(context, 'retry'),
      );
    }
    final partial = _parts
        .expand((p) => p.topics)
        .where((t) => t.textStatus.contains('ناقص'))
        .length;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.menu_book, color: AppColors.gold),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'البروتوكول والمراسم',
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'تأليف أسعد محمد منصور — القاهرة 2026م/1448هـ',
                  style: TextStyle(color: context.mutedColor),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_totalCount موضوعاً ببنية الكتاب: بابان وخمسة فصول ومباحثها، '
                  'إضافة إلى المادة الافتتاحية والملحقات والمراجع والفهرس.',
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 6),
                Text(
                  'حالة النص: «مصحح آلياً» — تصحيح آلي موثّق لاستخلاص نص '
                  'الكتاب، لا مراجعة بشرية.'
                  '${partial > 0 ? ' وموضوع واحد نصه جزئي (صور غير مستخرجة).' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.7,
                    color: context.mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ..._parts.map((part) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.navy,
                  child: Icon(_partIcon(part.name),
                      color: AppColors.gold, size: 22),
                ),
                title: Text(part.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${part.count} موضوعاً'
                  '${part.pagesLabel.isNotEmpty ? ' • ${part.pagesLabel}' : ''}',
                ),
                trailing: const Icon(Icons.arrow_back_ios, size: 14),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => BookPartPage(part: part)),
                ),
              ),
            )),
      ],
    );
  }
}

/// صفحة مستقلة لموسوعة الكتاب (تُفتح من الرئيسية ومن تبويب الموسوعة).
class BookEncyclopediaPage extends StatelessWidget {
  const BookEncyclopediaPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كتاب البروتوكول والمراسم')),
      body: const BookEncyclopediaView(),
    );
  }
}

// ── مستوى الجزء: فصوله، ثم مواضيعه المباشرة (بلا فصل) ──

class BookPartPage extends StatelessWidget {
  final BookPart part;
  const BookPartPage({super.key, required this.part});

  @override
  Widget build(BuildContext context) {
    final chapters = chaptersOf(part);
    return Scaffold(
      appBar: AppBar(title: Text(part.name)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${part.count} موضوعاً'
                '${part.pagesLabel.isNotEmpty ? ' • ${part.pagesLabel}' : ''}'
                ' — من كتاب «البروتوكول والمراسم»، تأليف أسعد محمد منصور.',
                style: const TextStyle(height: 1.7),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final ch in chapters)
            if (ch.name == '—')
              ..._mabhasSections(context, ch.topics)
            else
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.navy,
                    child: Icon(Icons.bookmark,
                        color: AppColors.gold, size: 20),
                  ),
                  title: Text(ch.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${ch.count} موضوعاً'
                    '${ch.pagesLabel.isNotEmpty ? ' • ${ch.pagesLabel}' : ''}',
                  ),
                  trailing: const Icon(Icons.arrow_back_ios, size: 14),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookChapterPage(
                        partName: part.name,
                        chapter: ch.name,
                        topics: ch.topics,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ── مستوى الفصل: مباحثه، ثم مواضيع كل مبحث ──

class BookChapterPage extends StatelessWidget {
  final String partName;
  final String chapter;
  final List<KbTopic> topics;
  const BookChapterPage({
    super.key,
    required this.partName,
    required this.chapter,
    required this.topics,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(chapter)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '$partName — $chapter'
                '${_rangeLabel(topics).isNotEmpty ? ' • ${_rangeLabel(topics)}' : ''}',
                style: const TextStyle(height: 1.7),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._mabhasSections(context, topics, showMabhasInTile: false),
        ],
      ),
    );
  }
}

/// أقسام المباحث داخل قائمة مواضيع: عنوان مبحث ثم بطاقات مواضيعه.
/// المباحث بلا اسم ('—') تُعرض مواضيعها مباشرة بلا عنوان.
List<Widget> _mabhasSections(
  BuildContext context,
  List<KbTopic> topics, {
  bool showMabhasInTile = true,
}) {
  final widgets = <Widget>[];
  for (final mabhas in mabhasOf(topics)) {
    if (mabhas.name != '—') {
      widgets.add(SectionHeader(title: mabhas.name));
      widgets.add(const SizedBox(height: 4));
    }
    for (final t in mabhas.topics) {
      widgets.add(_topicTile(context, t, showMabhas: showMabhasInTile));
    }
    widgets.add(const SizedBox(height: 8));
  }
  return widgets;
}

Widget _topicTile(BuildContext context, KbTopic t, {bool showMabhas = true}) {
  final pages = t.bookPagesLabel.isNotEmpty
      ? t.bookPagesLabel
      : (t.bookPageLabel ?? '');
  final crumbs = [
    if (showMabhas && t.mabhas != '—') t.mabhas,
    if (pages.isNotEmpty) pages,
  ].join(' • ');
  return Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      leading:
          const Icon(Icons.article_outlined, color: AppColors.navy),
      title: Text(t.title,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        crumbs.isEmpty
            ? t.excerpt
            : t.excerpt.isEmpty
                ? crumbs
                : '$crumbs\n${t.excerpt}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.arrow_back_ios, size: 14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => KbTopicReaderPage(topic: t)),
      ),
    ),
  );
}

// ── قارئ الموضوع: نص الموضوع كاملاً من قاعدة المعرفة ──

class KbTopicReaderPage extends StatelessWidget {
  final KbTopic topic;
  const KbTopicReaderPage({super.key, required this.topic});

  String get _pages {
    if (topic.bookPagesLabel.isNotEmpty) return topic.bookPagesLabel;
    return topic.bookPageLabel ?? '';
  }

  String get _citation {
    final pages = _pages;
    return 'المصدر: ${topic.source}'
        '${pages.isNotEmpty ? '، $pages' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final t = topic;
    final crumbs = [
      if (t.part != '—') t.part,
      if (t.chapter != '—') t.chapter,
      if (t.mabhas != '—') t.mabhas,
    ].join(' — ');
    final subsections = _jsonStringList(t.subsectionsJson);
    final hasAnyContent =
        (t.summary ?? '').trim().isNotEmpty ||
            (t.definition ?? '').trim().isNotEmpty ||
            (t.explanation ?? '').trim().isNotEmpty ||
            _jsonStringList(t.rulesJson).isNotEmpty ||
            _jsonStringList(t.proceduresJson).isNotEmpty ||
            _jsonStringList(t.examplesJson).isNotEmpty ||
            _jsonStringList(t.mistakesJson).isNotEmpty ||
            _jsonStringList(t.keyPointsJson).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.mabhas != '—' ? t.mabhas : (t.part != '—' ? t.part : t.title),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(
              '${t.title}\n'
              '${_pages.isNotEmpty ? '$_pages\n' : ''}\n'
              '${t.excerpt}\n\n$_citation',
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (crumbs.isNotEmpty)
              Text(
                crumbs,
                style: TextStyle(color: context.mutedColor, fontSize: 12.5),
              ),
            const SizedBox(height: 6),
            Text(
              t.title,
              style: const TextStyle(
                fontFamily: 'Amiri',
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_pages.isNotEmpty)
                  Chip(
                    label: Text(_pages,
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor: const Color(0xFFF3EDDD),
                  ),
                if (t.textStatus.isNotEmpty)
                  Chip(
                    label: Text('حالة النص: ${t.textStatus}',
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor: const Color(0xFFF3EDDD),
                  ),
              ],
            ),
            if ((t.contentLimitation ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber,
                          color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.contentLimitation!,
                          style:
                              const TextStyle(height: 1.8, fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (!hasAnyContent)
              const EmptyState(
                icon: Icons.article_outlined,
                text: 'لا يوجد نص مستخلص لهذا الموضوع في قاعدة المعرفة بعد.',
              )
            else ...[
              if (subsections.isNotEmpty) ...[
                const SectionHeader(title: 'العناوين الفرعية'),
                const SizedBox(height: 4),
                ...subsections.map((s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(s,
                                style: const TextStyle(height: 1.8)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 10),
              ],
              ..._bookTextSection('الخلاصة — من قاعدة المعرفة', t.summary),
              ..._bookTextSection('التعريف — من قاعدة المعرفة', t.definition),
              ..._bookTextSection('الشرح — من قاعدة المعرفة', t.explanation),
              ..._bookListSection(
                  'القواعد والمبادئ — من قاعدة المعرفة', t.rulesJson),
              ..._bookListSection(
                  'الإجراءات العملية — من قاعدة المعرفة', t.proceduresJson),
              ..._bookListSection(
                  'أمثلة — من قاعدة المعرفة حيثما وردت', t.examplesJson),
              ..._bookListSection('أخطاء شائعة — من قاعدة المعرفة حيثما وردت',
                  t.mistakesJson),
              ..._bookListSection(
                  'نقاط أساسية — من قاعدة المعرفة', t.keyPointsJson),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'حالة النص: «${t.textStatus}»',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.textStatus.contains('مصحح آلياً')
                          ? 'تصحيح آلي موثّق لاستخلاص نص الكتاب؛ لا تعني مراجعة بشرية.'
                          : t.textStatus.contains('ناقص')
                              ? 'نص جزئي؛ راجع قيد المحتوى أعلاه.'
                              : 'كما هي مسجلة في قاعدة المعرفة.',
                      style: const TextStyle(height: 1.8, fontSize: 13.5),
                    ),
                    if (t.correctionsApplied > 0)
                      Text(
                        'طُبّق ${t.correctionsApplied} تصحيحاً آلياً موثقاً على هذا الموضوع.',
                        style:
                            const TextStyle(height: 1.8, fontSize: 13.5),
                      ),
                    if (t.residualGarbleCount > 0)
                      Text(
                        'وبقي ${t.residualGarbleCount} موضعاً مشوّهاً يحتاج مراجعة بشرية.',
                        style:
                            const TextStyle(height: 1.8, fontSize: 13.5),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(_citation, style: const TextStyle(height: 1.8)),
            const SizedBox(height: 12),
            SourceLine(
              sourceName: t.source,
              sourceOrg: 'تأليف أسعد محمد منصور — القاهرة 2026م/1448هـ',
              sourceUrl: '',
              reviewed: '',
              ruleType: 'من كتاب «البروتوكول والمراسم»',
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _bookTextSection(String title, String? body) {
  if (body == null || body.trim().isEmpty) return const [];
  return [
    SectionHeader(title: title),
    const SizedBox(height: 6),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(body.trim(),
            style: const TextStyle(height: 1.9, fontSize: 15)),
      ),
    ),
    const SizedBox(height: 14),
  ];
}

List<Widget> _bookListSection(String title, String? rawJson) {
  final items = _jsonStringList(rawJson);
  if (items.isEmpty) return const [];
  return [
    SectionHeader(title: title),
    const SizedBox(height: 6),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: items
              .map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ',
                            style: TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Text(s,
                              style: const TextStyle(height: 1.9)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    ),
    const SizedBox(height: 14),
  ];
}
