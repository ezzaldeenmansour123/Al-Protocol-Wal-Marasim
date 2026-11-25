import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'academy.dart';
import 'app_state.dart';
import 'assistant.dart';
import 'book_encyclopedia.dart';
import 'db.dart';
import 'encyclopedia.dart';
import 'library.dart';
import 'model_settings.dart';
import 'notifications.dart';
import 'sections.dart';
import 'tools.dart';
import 'widgets.dart';

Future<void> scheduleNationalDayReminders() async {
  final days = await Repo.i.upcomingNationalDays(days: 60);
  for (final d in days) {
    await NotificationService.schedule(
      id: 20000 + d.countryId,
      title: 'العيد الوطني — ${d.countryAr}',
      body: 'اليوم ${d.name} (${d.countryAr}).',
      when: DateTime(d.nextDate.year, d.nextDate.month, d.nextDate.day, 9),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final state = AppState();
  await state.load();
  await NotificationService.requestPermissions();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const ProtocolCeremonialApp(),
    ),
  );
}

class ProtocolCeremonialApp extends StatelessWidget {
  const ProtocolCeremonialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (ctx, state, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'البروتوكول والمراسم | PROTOCOL & CEREMONIAL',
        locale: Locale(state.language),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: AppTheme.light(state.fontScale),
        darkTheme: AppTheme.dark(state.fontScale),
        themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: const SplashPage(),
      ),
    );
  }
}

// ── Splash ──
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zoom;

  @override
  void initState() {
    super.initState();
    _zoom = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..forward();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomePage()));
      }
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle animated photo backdrop: slow Ken Burns zoom.
          ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.12).animate(
                CurvedAnimation(parent: _zoom, curve: Curves.easeOut)),
            child: Image.asset('assets/images/hero1.jpg',
                fit: BoxFit.cover,
                errorBuilder: (c, e, st) =>
                    Container(color: AppColors.navy)),
          ),
          Container(color: AppColors.navy.withValues(alpha: 0.82)),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/logo.png',
                    width: 220,
                    height: 220,
                    errorBuilder: (c, e, st) => const Icon(Icons.public,
                        color: AppColors.gold, size: 120)),
                const SizedBox(height: 8),
                const Text('البروتوكول والمراسم',
                    style: TextStyle(
                        fontFamily: 'Amiri',
                        color: AppColors.gold,
                        fontSize: 30,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('PROTOCOL & CEREMONIAL',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 40),
                const CircularProgressIndicator(color: AppColors.gold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home (bottom nav) ──
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  bool _remindersScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_remindersScheduled) return;
      _remindersScheduled = true;
      final state = Provider.of<AppState>(context, listen: false);
      if (state.notifDays) await scheduleNationalDayReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final pages = [
      HomeTab(onGoTab: (i) => setState(() => _index = i)),
      const EncyclopediaHubPage(),
      const AssistantPage(),
      const ToolsHubPage(),
      const AcademyPage(),
      const ArchivesPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        selectedItemColor: AppColors.navy,
        unselectedItemColor: AppColors.stone,
        onTap: (i) => setState(() => _index = i),
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.home), label: tr(state, 'home')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.menu_book),
              label: tr(state, 'nav_encyclopedia')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.smart_toy),
              label: tr(state, 'nav_assistant')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.build),
              label: tr(state, 'nav_tools')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.school),
              label: tr(state, 'nav_academy')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.archive),
              label: tr(state, 'nav_archives')),
        ],
      ),
    );
  }
}

// ── Home tab (v2 §8) ──
// Logo + name, short welcome, prominent PROTOCOL AI card, the six main
// sections, latest topics, continue-last-reading, tool shortcuts and the
// upcoming national days. Contact details never appear here (§1).
class HomeTab extends StatefulWidget {
  final void Function(int) onGoTab;
  const HomeTab({super.key, required this.onGoTab});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Article> _latest = [];
  List<NationalDayItem> _upcoming = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final latest = await Repo.i.latestArticles(limit: 4);
    final upcoming = await Repo.i.upcomingNationalDays(days: 30);
    if (!mounted) return;
    setState(() {
      _latest = latest;
      _upcoming = upcoming;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    // The six main sections (§4): five switch the bottom-nav tab, and
    // References & Sources opens its page (it also lives in the
    // Encyclopedia hub).
    final sections = [
      (Icons.menu_book, tr(state, 'encyclopedia'),
          tr(state, 'encyclopedia_sub'), () => widget.onGoTab(1)),
      (Icons.smart_toy, tr(state, 'assistant'), tr(state, 'assistant_sub'),
          () => widget.onGoTab(2)),
      (Icons.build, tr(state, 'tools_title'), tr(state, 'tools_sub'),
          () => widget.onGoTab(3)),
      (Icons.school, tr(state, 'academy'), tr(state, 'academy_sub'),
          () => widget.onGoTab(4)),
      (Icons.library_books, tr(state, 'nav_references'),
          tr(state, 'references_sub'),
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const LibraryPage()))),
      (Icons.archive, tr(state, 'archives'), tr(state, 'archives_sub'),
          () => widget.onGoTab(5)),
    ];
    final shortcuts = [
      (Icons.format_list_numbered, tr(state, 'tool_precedence'),
          const PrecedencePage()),
      (Icons.event_seat, tr(state, 'tool_seating'),
          const SeatingPlansPage()),
      (Icons.event, tr(state, 'tool_events'), const EventsPage()),
      (Icons.description, tr(state, 'tool_docs'),
          const DocGeneratorPage()),
      (Icons.fact_check, tr(state, 'tool_checker'),
          const CheckerPickerPage()),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png',
                width: 34,
                height: 34,
                errorBuilder: (c, e, st) => const Icon(Icons.public,
                    color: AppColors.gold)),
            const SizedBox(width: 8),
            const Text('البروتوكول والمراسم'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: tr(state, 'assistant'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AssistantPage())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr(state, 'settings'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AnimatedBackground(),
          RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome: logo, full v2 name, short greeting.
                  Center(
                    child: Column(
                      children: [
                        Image.asset('assets/logo.png',
                            width: 96,
                            height: 96,
                            errorBuilder: (c, e, st) => const Icon(
                                Icons.public,
                                color: AppColors.gold,
                                size: 64)),
                        const SizedBox(height: 8),
                        const Text('البروتوكول والمراسم',
                            style: TextStyle(
                                fontFamily: 'Amiri',
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const Text('PROTOCOL & CEREMONIAL',
                            style: TextStyle(
                                color: AppColors.goldLight,
                                fontSize: 13,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 6),
                        Text(tr(state, 'home_welcome'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13.5, height: 1.7)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SearchPage())),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: AppColors.stone),
                          const SizedBox(width: 8),
                          Text(tr(state, 'search_hint'),
                              style: const TextStyle(color: AppColors.stone)),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 14),
              // The book itself, featured on Home: opens the book
              // encyclopedia (54 topics in the book's own structure)
              // directly. No cover image is bundled in assets/images in
              // this tree, so the card uses a book icon — no cover art
              // is invented.
              InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BookEncyclopediaPage())),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.gold, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.menu_book,
                            color: AppColors.gold, size: 32),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'البروتوكول والمراسم',
                              style: TextStyle(
                                fontFamily: 'Amiri',
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              'تأليف أسعد محمد منصور • 54 موضوعاً ببنية الكتاب',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.mutedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_back_ios, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // AI assistant banner — the most prominent section (§4.2).
              InkWell(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AssistantPage())),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      AppColors.navy,
                      AppColors.navyLight,
                    ]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.gold),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.smart_toy,
                          color: AppColors.gold, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(state, 'assistant_full'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17)),
                            Text(
                                tr(state, 'assistant_desc'),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_back_ios,
                          color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SectionHeader(title: tr(state, 'sections_title')),
              const SizedBox(height: 6),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.6,
                children: sections
                    .map((s) => InkWell(
                          onTap: s.$4,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: context.cardBorderColor),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(s.$1,
                                    color: AppColors.gold, size: 26),
                                const SizedBox(height: 6),
                                Text(s.$2,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5)),
                                Text(s.$3,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: context.mutedColor)),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              SectionHeader(title: tr(state, 'continue_reading')),
              const SizedBox(height: 6),
              const LastReadCard(),
              const SizedBox(height: 14),
              SectionHeader(
                title: tr(state, 'latest'),
                onMore: () => widget.onGoTab(1),
              ),
              const SizedBox(height: 6),
              ..._latest.map((a) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const Icon(Icons.article_outlined,
                          color: AppColors.navy),
                      title: Text(a.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(a.section),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ArticleReaderPage(article: a)),
                      ),
                    ),
                  )),
              const SizedBox(height: 14),
              SectionHeader(title: tr(state, 'tool_shortcuts')),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: shortcuts
                      .map((s) => Padding(
                            padding:
                                const EdgeInsetsDirectional.only(end: 8),
                            child: ActionChip(
                              avatar: Icon(s.$1,
                                  size: 18, color: AppColors.gold),
                              label: Text(s.$2),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => s.$3)),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 14),
              SectionHeader(title: tr(state, 'upcoming')),
              const SizedBox(height: 6),
              if (_upcoming.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(tr(state, 'no_national_days'),
                        style: const TextStyle(color: AppColors.stone)),
                  ),
                )
              else
                ..._upcoming.map((d) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: Text(d.flag,
                            style: const TextStyle(fontSize: 26)),
                        title: Text('${d.countryAr} — ${d.name}'),
                        subtitle: Text(
                            '${d.nextDate.year}-${d.nextDate.month.toString().padLeft(2, '0')}-${d.nextDate.day.toString().padLeft(2, '0')}'),
                      ),
                    )),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }
}

// ── Global search ──
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  List<Article> _articles = [];
  List<Country> _countries = [];
  List<TemplateDoc> _templates = [];
  bool _searched = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _articles = [];
        _countries = [];
        _templates = [];
        _searched = false;
      });
      return;
    }
    final a = await Repo.i.searchArticles(q);
    final c = await Repo.i.searchCountries(q);
    final t = await Repo.i.searchTemplates(q);
    if (!mounted) return;
    setState(() {
      _articles = a;
      _countries = c;
      _templates = t;
      _searched = true;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: tr(state, 'search'),
              hintStyle: const TextStyle(color: Colors.white70),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search, color: Colors.white),
            ),
            onChanged: _search,
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: tr(state, 'tab_articles')),
              Tab(text: tr(state, 'tab_countries')),
              Tab(text: tr(state, 'tab_templates')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _resultsList<Article>(
              _articles,
              (a) => ListTile(
                leading:
                    const Icon(Icons.article_outlined, color: AppColors.navy),
                title: Text(a.title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(a.section),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ArticleReaderPage(article: a)),
                ),
              ),
            ),
            _resultsList<Country>(
              _countries,
              (c) => ListTile(
                leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                title: Text(c.nameAr,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.nameEn} • ${c.capital}'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CountryDetailPage(country: c)),
                ),
              ),
            ),
            _resultsList<TemplateDoc>(
              _templates,
              (t) => ListTile(
                leading:
                    const Icon(Icons.description, color: AppColors.navy),
                title: Text(t.titleAr,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(t.category),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          DocGeneratorPage(templateKey: t.key)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsList<T>(List<T> items, Widget Function(T) tile) {
    if (!_searched) {
      return EmptyState(
          icon: Icons.search, text: trc(context, 'search_empty_hint'));
    }
    if (items.isEmpty) {
      return EmptyState(
          icon: Icons.search_off, text: trc(context, 'search_no_results'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (ctx, i) => Card(child: tile(items[i])),
    );
  }
}

// ── Favorites ──
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});
  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Article> _articles = [];
  List<Country> _countries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await Repo.i.favArticles();
    final c = await Repo.i.favCountries();
    if (mounted) {
      setState(() {
        _articles = a;
        _countries = c;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(trc(context, 'favorites'))),
      body: (_articles.isEmpty && _countries.isEmpty)
          ? EmptyState(
              icon: Icons.star_border,
              text: trc(context, 'favorites_empty'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_articles.isNotEmpty) ...[
                    SectionHeader(title: trc(context, 'favorites_articles')),
                    ..._articles.map((a) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.article_outlined,
                                color: AppColors.navy),
                            title: Text(a.title),
                            subtitle: Text(a.section),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ArticleReaderPage(article: a)),
                            ),
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],
                  if (_countries.isNotEmpty) ...[
                    SectionHeader(title: trc(context, 'favorites_countries')),
                    ..._countries.map((c) => Card(
                          child: ListTile(
                            leading: Text(c.flag,
                                style: const TextStyle(fontSize: 26)),
                            title: Text(c.nameAr),
                            subtitle: Text(c.capital),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      CountryDetailPage(country: c)),
                            ),
                          ),
                        )),
                  ],
                ],
              ),
            ),
    );
  }
}

// ── Settings ──
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = Provider.of<AppState>(context, listen: false);
    _apiCtrl.text = state.apiKey;
  }

  @override
  void dispose() {
    _apiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(state, 'settings'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: tr(state, 'settings_language')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.language == 'ar'
                          ? AppColors.navy
                          : Colors.grey[300],
                      foregroundColor: state.language == 'ar'
                          ? Colors.white
                          : Colors.black,
                    ),
                    onPressed: () => state.setLanguage('ar'),
                    child: const Text('العربية'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.language == 'en'
                          ? AppColors.navy
                          : Colors.grey[300],
                      foregroundColor: state.language == 'en'
                          ? Colors.white
                          : Colors.black,
                    ),
                    onPressed: () => state.setLanguage('en'),
                    child: const Text('English'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionHeader(title: tr(state, 'settings_font')),
            Row(
              children: [
                IconButton(
                  icon: const Text('A−',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  onPressed: () =>
                      state.setFontScale(state.fontScale - 0.1),
                ),
                Expanded(
                  child: Slider(
                    value: state.fontScale,
                    min: 0.9,
                    max: 1.3,
                    divisions: 4,
                    label: state.fontScale.toStringAsFixed(1),
                    onChanged: (v) => state.setFontScale(v),
                  ),
                ),
                IconButton(
                  icon: const Text('A+',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  onPressed: () =>
                      state.setFontScale(state.fontScale + 0.1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(tr(state, 'settings_dark')),
              subtitle: Text(tr(state, 'settings_dark_sub')),
              value: state.darkMode,
              onChanged: (v) => state.setDarkMode(v),
            ),
            SwitchListTile(
              title: Text(tr(state, 'settings_notif_days')),
              subtitle: Text(tr(state, 'settings_notif_days_sub')),
              value: state.notifDays,
              onChanged: (v) async {
                await state.setNotifDays(v);
                if (v) await scheduleNationalDayReminders();
              },
            ),
            SwitchListTile(
              title: Text(tr(state, 'settings_notif_events')),
              subtitle: Text(tr(state, 'settings_notif_events_sub')),
              value: state.notifEvents,
              onChanged: (v) => state.setNotifEvents(v),
            ),
            const SizedBox(height: 16),
            SectionHeader(title: tr(state, 'settings_generative')),
            const SizedBox(height: 6),
            Text(
              tr(state, 'settings_generative_desc'),
              style: const TextStyle(color: AppColors.stone, height: 1.7),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: tr(state, 'settings_api_label'),
                hintText: 'sk-...',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await state.setApiKey(_apiCtrl.text);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr(state, 'settings_key_saved'))));
                    }
                  },
                  child: Text(tr(state, 'settings_save_key')),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    await scheduleNationalDayReminders();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr(state, 'settings_rescheduled'))));
                    }
                  },
                  child: Text(tr(state, 'settings_reschedule')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // P6 — قسم النموذج المحلي (تنزيل/حذف/حالة) في الإعدادات.
            const ModelSettingsSection(),
            const SizedBox(height: 16),
            Text('البروتوكول والمراسم — ${tr(state, 'version')} $appVersion',
                style: const TextStyle(color: AppColors.stone)),
          ],
        ),
      ),
    );
  }
}

// ── About & Contact (v2 §1 — founder/contact info lives ONLY here) ──
// Contact details (email + phone, tappable mailto:/tel:) appear on this
// page only — never on Home or any other screen.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(trc(context, 'open_link_failed'))));
      }
    }
  }

  Widget _section(BuildContext context, String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(body,
                style: const TextStyle(height: 1.9, fontSize: 14.5)),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(trc(context, 'about'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png',
                width: 150,
                height: 150,
                errorBuilder: (c, e, st) => const Icon(Icons.public,
                    color: AppColors.gold, size: 90)),
            const SizedBox(height: 12),
            Text('البروتوكول والمراسم',
                style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: context.headingColor)),
            const Text('PROTOCOL & CEREMONIAL',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.stone, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Text(
              trc(context, 'about_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.9, fontSize: 15),
            ),
            const SizedBox(height: 20),
            _section(context, trc(context, 'about_goals'),
                trc(context, 'about_goals_body')),
            // Attribution — content/reference vs programming/design (§1).
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person,
                            color: AppColors.gold),
                        const SizedBox(width: 8),
                        Text(trc(context, 'about_owner'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(trc(context, 'about_owner_name'),
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.code,
                            color: AppColors.gold),
                        const SizedBox(width: 8),
                        Text(trc(context, 'about_dev'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(trc(context, 'about_dev_name'),
                        style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SectionHeader(title: trc(context, 'about_contact')),
            ),
            const SizedBox(height: 6),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading:
                        const Icon(Icons.email, color: AppColors.gold),
                    title: Text(trc(context, 'about_email_label')),
                    subtitle: const Text('Ezzaldeenmansour22@gmail.com',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right),
                    trailing:
                        const Icon(Icons.open_in_new, size: 16),
                    onTap: () => _open(context,
                        Uri(scheme: 'mailto', path: 'Ezzaldeenmansour22@gmail.com')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        const Icon(Icons.phone, color: AppColors.gold),
                    title: Text(trc(context, 'about_phone_label')),
                    subtitle: const Text('770642229',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right),
                    trailing:
                        const Icon(Icons.open_in_new, size: 16),
                    onTap: () => _open(
                        context, Uri(scheme: 'tel', path: '770642229')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        const Icon(Icons.link, color: AppColors.gold),
                    title: Text(trc(context, 'about_github_label')),
                    subtitle: const Text(
                        'https://github.com/ezzaldeenmansour123',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right),
                    trailing:
                        const Icon(Icons.open_in_new, size: 16),
                    onTap: () => _open(context,
                        Uri.parse('https://github.com/ezzaldeenmansour123')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _section(context, trc(context, 'about_rights'),
                trc(context, 'about_rights_body')),
            _section(context, trc(context, 'about_privacy_title'),
                trc(context, 'about_privacy_body')),
            _section(context, trc(context, 'about_terms_title'),
                trc(context, 'about_terms_body')),
            Text(
              trc(context, 'about_disclaimer'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.stone, height: 1.7),
            ),
            const SizedBox(height: 8),
            Text('${trc(context, 'version')} $appVersion',
                style: const TextStyle(color: AppColors.stone)),
          ],
        ),
      ),
    );
  }
}
