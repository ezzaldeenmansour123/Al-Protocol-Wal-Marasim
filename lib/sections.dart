import 'package:material_ui/material_ui.dart';
import 'app_state.dart';
import 'assistant.dart';
import 'db.dart';
import 'encyclopedia.dart';
import 'library.dart';
import 'main.dart';
import 'saved_chats.dart';
import 'tools.dart';
import 'widgets.dart';

/// v2 §4 — the six main sections, regrouped from the existing screens.
/// No existing function is removed: the guide, countries and library keep
/// working exactly as before, now reached through the Encyclopedia hub and
/// the home grid. Academy and Archives are new sections; their content
/// depending on the book is honestly marked "in preparation" (see below).

/// Card shown on Home and in Archives: resumes the last article opened.
/// The article id is stored in settings by ArticleReaderPage; nothing is
/// stored until the user actually opens an article.
class LastReadCard extends StatefulWidget {
  const LastReadCard({super.key});
  @override
  State<LastReadCard> createState() => _LastReadCardState();
}

class _LastReadCardState extends State<LastReadCard> {
  Article? _article;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final idStr = await Repo.i.getSetting('last_read_article_id', '');
    final id = int.tryParse(idStr);
    if (id == null) return;
    final a = await Repo.i.articleById(id);
    if (mounted && a != null) setState(() => _article = a);
  }

  @override
  Widget build(BuildContext context) {
    final a = _article;
    if (a == null) {
      return Card(
        child: ListTile(
          leading:
              const Icon(Icons.history, color: AppColors.gold),
          title: Text(trc(context, 'continue_reading'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(trc(context, 'continue_reading_empty')),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ProtocolGuidePage())),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.history, color: AppColors.gold),
        title: Text(trc(context, 'continue_reading'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${a.title} — ${a.section}'),
        trailing: const Icon(Icons.arrow_back_ios, size: 14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ArticleReaderPage(article: a)),
        ),
      ),
    );
  }
}

/// 1. الموسوعة — hub for the protocol guide, the countries encyclopedia
/// and references & sources (the former Library page).
class EncyclopediaHubPage extends StatelessWidget {
  const EncyclopediaHubPage({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.menu_book,
        trc(context, 'guide_title'),
        trc(context, 'guide_sub'),
        const ProtocolGuidePage(),
      ),
      (
        Icons.public,
        trc(context, 'countries'),
        trc(context, 'countries_count_sub'),
        const CountriesPage(),
      ),
      (
        Icons.library_books,
        trc(context, 'nav_references'),
        trc(context, 'references_sub'),
        const LibraryPage(),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(trc(context, 'nav_encyclopedia'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.search, color: AppColors.gold),
              title: Text(trc(context, 'search_hint')),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SearchPage())),
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((it) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.navy,
                    child: Icon(it.$1, color: AppColors.gold, size: 22),
                  ),
                  title: Text(it.$2,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(it.$3),
                  trailing: const Icon(Icons.arrow_back_ios, size: 14),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => it.$4)),
                ),
              )),
        ],
      ),
    );
  }
}

/// 6. المحفوظات (§4.6) — favorites, saved conversations, the user's own
/// documents and plans, and activity. Saved conversations are real now:
/// the assistant auto-saves every exchange on-device (lib/assistant.dart
/// + lib/saved_chats.dart); opening a conversation shows it in full,
/// deleting asks for confirmation.
class ArchivesPage extends StatelessWidget {
  const ArchivesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(trc(context, 'archives_title'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionHeader(title: trc(context, 'favorites')),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading: const Icon(Icons.star, color: AppColors.gold),
              title: Text(trc(context, 'favorites'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(trc(context, 'favorites_articles')),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FavoritesPage())),
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader(title: trc(context, 'archives_chats')),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.chat_bubble_outline, color: AppColors.gold),
              title: Text(trc(context, 'archives_chats'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(trc(context, 'archives_chats_sub')),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SavedConversationsPage())),
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader(title: trc(context, 'archives_docs')),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading: const Icon(Icons.people, color: AppColors.navy),
              title: Text(trc(context, 'tool_delegations'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DelegationsPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.flight_takeoff, color: AppColors.navy),
              title: Text(trc(context, 'tool_visits'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const VisitsPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups, color: AppColors.navy),
              title: Text(trc(context, 'tool_conferences'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ConferencesPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.dinner_dining, color: AppColors.navy),
              title: Text(trc(context, 'tool_banquets'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BanquetsPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event, color: AppColors.navy),
              title: Text(trc(context, 'archives_events'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EventsPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_seat, color: AppColors.navy),
              title: Text(trc(context, 'archives_plans'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SeatingPlansPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.description, color: AppColors.navy),
              title: Text(trc(context, 'tool_docs'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DocGeneratorPage())),
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader(title: trc(context, 'archives_activity')),
          const SizedBox(height: 6),
          const LastReadCard(),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings, color: AppColors.navy),
              title: Text(trc(context, 'settings'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.info_outline, color: AppColors.navy),
              title: Text(trc(context, 'about'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_back_ios, size: 14),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AboutPage())),
            ),
          ),
        ],
      ),
    );
  }
}
