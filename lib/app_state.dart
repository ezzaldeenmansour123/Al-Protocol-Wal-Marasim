import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'db.dart';

/// App-wide state: language, font size, notifications, night mode and the
/// optional (future) generative API key. All values persist in the settings
/// table so they survive restarts.
class AppState extends ChangeNotifier {
  String language = 'ar';
  double fontScale = 1.0;
  bool notifDays = true;
  bool notifEvents = true;
  bool darkMode = false;
  String apiKey = '';

  Future<void> load() async {
    language = await Repo.i.getSetting('language', 'ar');
    fontScale =
        double.tryParse(await Repo.i.getSetting('font_scale', '1.0')) ?? 1.0;
    notifDays = (await Repo.i.getSetting('notif_days', '1')) == '1';
    notifEvents = (await Repo.i.getSetting('notif_events', '1')) == '1';
    darkMode = (await Repo.i.getSetting('dark_mode', '0')) == '1';
    apiKey = await Repo.i.getSetting('api_key', '');
    notifyListeners();
  }

  Future<void> setLanguage(String v) async {
    language = v;
    await Repo.i.setSetting('language', v);
    notifyListeners();
  }

  Future<void> setFontScale(double v) async {
    fontScale = v.clamp(0.9, 1.3);
    await Repo.i.setSetting('font_scale', fontScale.toStringAsFixed(2));
    notifyListeners();
  }

  Future<void> setNotifDays(bool v) async {
    notifDays = v;
    await Repo.i.setSetting('notif_days', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setNotifEvents(bool v) async {
    notifEvents = v;
    await Repo.i.setSetting('notif_events', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setDarkMode(bool v) async {
    darkMode = v;
    await Repo.i.setSetting('dark_mode', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setApiKey(String v) async {
    apiKey = v.trim();
    await Repo.i.setSetting('api_key', apiKey);
    notifyListeners();
  }
}

/// All user-visible UI chrome (labels, buttons, hints, empty states, dialogs)
/// in Arabic and English. Article and country CONTENT stays Arabic with
/// English names — translating the knowledge base itself is a separate
/// effort, noted in the README.
const _strings = {
  // Navigation — v2 §4: six main sections. The bottom bar holds Home +
  // Encyclopedia + Assistant + Tools + Academy + Archives; References &
  // Sources is reached from the home grid and from the Encyclopedia hub.
  'home': {'ar': 'الرئيسية', 'en': 'Home'},
  'nav_encyclopedia': {'ar': 'الموسوعة', 'en': 'Encyclopedia'},
  'nav_assistant': {'ar': 'المساعد', 'en': 'Assistant'},
  'nav_tools': {'ar': 'الأدوات', 'en': 'Tools'},
  'nav_academy': {'ar': 'الأكاديمية', 'en': 'Academy'},
  'nav_archives': {'ar': 'المحفوظات', 'en': 'Archives'},
  'nav_references': {'ar': 'المراجع والمصادر', 'en': 'References & Sources'},
  'library': {'ar': 'المراجع والمصادر', 'en': 'References & Sources'},
  'assistant': {'ar': 'المساعد الذكي', 'en': 'AI Assistant'},
  'assistant_full': {'ar': 'PROTOCOL AI — المساعد الذكي', 'en': 'PROTOCOL AI'},
  // Home (v2 §8)
  'home_welcome': {
    'ar':
        'مرجعك في البروتوكول والمراسم والتشريفات — معرفة موثقة، وأدوات عملية، ومساعد ذكي.',
    'en':
        'Your reference for protocol, ceremonial and etiquette — sourced knowledge, practical tools and a smart assistant.'
  },
  'sections_title': {'ar': 'الأقسام الرئيسية', 'en': 'Main sections'},
  'encyclopedia': {'ar': 'الموسوعة', 'en': 'Encyclopedia'},
  'encyclopedia_sub': {
    'ar': 'دليل البروتوكول وموسوعة الدول',
    'en': 'Protocol guide and countries encyclopedia'
  },
  'academy': {'ar': 'الأكاديمية والتدريب', 'en': 'Academy & Training'},
  'academy_sub': {
    'ar': 'مستويات ودروس واختبارات',
    'en': 'Levels, lessons and quizzes'
  },
  'archives': {'ar': 'المحفوظات', 'en': 'Archives'},
  'archives_sub': {
    'ar': 'مفضلة ومستندات وخطط محفوظة',
    'en': 'Favorites, documents and saved plans'
  },
  'references_sub': {
    'ar': 'وثائق واتفاقيات ونماذج معتمدة',
    'en': 'Documents, conventions and templates'
  },
  'tools_sub': {
    'ar': 'أسبقية وجلوس ومناسبات ومستندات',
    'en': 'Precedence, seating, events and documents'
  },
  'assistant_sub': {
    'ar': 'اسأل واحصل على إجابة موثقة',
    'en': 'Ask and get a sourced answer'
  },
  'continue_reading': {'ar': 'متابعة آخر قراءة', 'en': 'Continue reading'},
  'continue_reading_empty': {
    'ar': 'لم تقرأ أي موضوع بعد — ابدأ من الموسوعة.',
    'en': 'No article read yet — start from the Encyclopedia.'
  },
  'tool_shortcuts': {
    'ar': 'اختصارات الأدوات العملية',
    'en': 'Practical tool shortcuts'
  },
  'guide_sub': {
    'ar': '49 مقالاً موثقاً في 16 قسماً',
    'en': '49 sourced articles in 16 sections'
  },
  'countries_count_sub': {
    'ar': '30 دولة — بحث وتفاصيل وبروتوكول محلي',
    'en': '30 countries — search, details and local protocol'
  },
  // Home
  'search_hint': {
    'ar': 'ابحث في البروتوكول والدول والنماذج...',
    'en': 'Search protocol, countries, templates...'
  },
  'assistant_desc': {
    'ar': 'اسأل عن أي قاعدة بروتوكولية — إجابات موثقة بالمصادر، دون إنترنت',
    'en': 'Ask any protocol question — sourced answers, fully offline'
  },
  'protocol': {'ar': 'البروتوكول الدبلوماسي', 'en': 'Diplomatic Protocol'},
  'ceremonies': {'ar': 'المراسم الرسمية', 'en': 'Official Ceremonies'},
  'flags': {'ar': 'الأعلام والرموز', 'en': 'Flags & Symbols'},
  'precedence': {'ar': 'الأسبقية والألقاب', 'en': 'Precedence & Titles'},
  'etiquette': {'ar': 'الإتيكيت الدولي', 'en': 'International Etiquette'},
  'events': {'ar': 'إدارة المناسبات', 'en': 'Event Management'},
  'countries': {'ar': 'موسوعة الدول', 'en': 'Countries Encyclopedia'},
  'countries_sub': {
    'ar': 'معلومات الدول وبروتوكولها المحلي',
    'en': 'Country facts and local protocol'
  },
  'latest': {'ar': 'أحدث المقالات', 'en': 'Latest Articles'},
  'upcoming': {
    'ar': 'المناسبات الوطنية القادمة',
    'en': 'Upcoming National Days'
  },
  'no_national_days': {
    'ar': 'لا توجد أعياد وطنية خلال الثلاثين يومًا القادمة.',
    'en': 'No national days in the next 30 days.'
  },
  'view_all': {'ar': 'عرض الكل', 'en': 'View all'},
  'hero_caption': {
    'ar': 'البروتوكول والمراسم — منصة البروتوكول الدولي',
    'en': 'PROTOCOL & CEREMONIAL — International Protocol & Diplomatic Affairs'
  },
  // Search
  'search': {'ar': 'ابحث...', 'en': 'Search...'},
  'tab_articles': {'ar': 'المقالات', 'en': 'Articles'},
  'tab_countries': {'ar': 'الدول', 'en': 'Countries'},
  'tab_templates': {'ar': 'النماذج', 'en': 'Templates'},
  'search_empty_hint': {
    'ar': 'اكتب كلمة للبحث في المقالات والدول والنماذج.',
    'en': 'Type a word to search articles, countries and templates.'
  },
  'search_no_results': {
    'ar': 'لا توجد نتائج مطابقة.',
    'en': 'No matching results.'
  },
  // Assistant
  'assistant_welcome': {
    'ar':
        'مرحبًا، أنا مساعد البروتوكول والمراسم الذكي. أسألني عن أي قاعدة بروتوكولية، وسأجيبك من قاعدة المعرفة الموثوقة مع ذكر المصدر. أعمل دون إنترنت.',
    'en':
        'Hello, I am the PROTOCOL assistant. Ask me any protocol question and I will answer from the trusted knowledge base, citing the source. I work fully offline.'
  },
  'assistant_searching': {
    'ar': 'أبحث في قاعدة المعرفة...',
    'en': 'Searching the knowledge base...'
  },
  'assistant_no_info': {
    'ar':
        'لا تتوفر في قاعدة المعرفة الحالية معلومات موثوقة وكافية للإجابة عن هذا السؤال.',
    'en':
        'There is no reliable and sufficient information in the current knowledge base to answer this question.'
  },
  'assistant_search_error': {
    'ar':
        'حدث خطأ أثناء البحث في قاعدة المعرفة. جرّب مرة أخرى، أو تصفّح دليل البروتوكول مباشرة.',
    'en':
        'An error occurred while searching the knowledge base. Please try again, or browse the protocol guide directly.'
  },
  'assistant_answer_intro': {
    'ar': 'إليك الإجابة من قاعدة المعرفة:',
    'en': 'Here is the answer from the knowledge base:'
  },
  'assistant_related': {'ar': 'مواضيع ذات صلة:', 'en': 'Related topics:'},
  'assistant_offline_note': {
    'ar': 'يعمل دون إنترنت — إجابات موثقة بالمصادر',
    'en': 'Works offline — answers cited with sources'
  },
  'assistant_how_title': {
    'ar': 'كيف يعمل المساعد؟',
    'en': 'How does the assistant work?'
  },
  'assistant_how_body': {
    'ar':
        'المساعد يبحث فقط في قاعدة المعرفة الموثوقة داخل التطبيق، ويذكر مصدر كل إجابة وتاريخ مراجعتها. لا يخترع قواعد أو ألقابًا أو مراتب أسبقية. إن لم تتوفر معلومة موثوقة يقول ذلك بوضوح. يعمل دون إنترنت. يمكن إضافة مفتاح API اختياري من الإعدادات لوضع توليدي مستقبلي — والتطبيق يعمل كاملًا بدونه.',
    'en':
        'The assistant searches only the trusted knowledge base inside the app and cites the source and review date of every answer. It never invents rules, titles, or precedence ranks. If no reliable information exists, it says so clearly. It works offline. An optional API key can be added in Settings for a future generative mode — the app works fully without it.'
  },
  'assistant_understood': {'ar': 'فهمت', 'en': 'Understood'},
  'assistant_draft': {'ar': 'صياغة مستند', 'en': 'Draft a document'},
  'assistant_draft_sub': {
    'ar': 'اختر النموذج، واملأ الحقول، وسيُصاغ المستند من القالب المعتمد.',
    'en':
        'Choose a template, fill in the fields, and the document will be drafted from the approved form.'
  },
  'assistant_check_plan': {
    'ar': 'مراجعة خطة مناسبة',
    'en': 'Review an event plan'
  },
  'assistant_write_question': {
    'ar': 'اكتب سؤالك هنا...',
    'en': 'Type your question here...'
  },
  'assistant_browse_guide': {
    'ar': 'تصفح دليل البروتوكول',
    'en': 'Browse the protocol guide'
  },
  'draft_invitation': {'ar': 'دعوة رسمية', 'en': 'Formal invitation'},
  'draft_visit_program': {
    'ar': 'برنامج زيارة رسمية',
    'en': 'Official visit program'
  },
  'draft_meeting_agenda': {'ar': 'جدول اجتماع', 'en': 'Meeting agenda'},
  'draft_event_checklist': {
    'ar': 'قائمة تحقق لمناسبة',
    'en': 'Event checklist'
  },
  // Encyclopedia / countries
  'countries_search_hint': {
    'ar': 'ابحث عن دولة أو عاصمة...',
    'en': 'Search for a country or capital...'
  },
  'countries_no_match': {
    'ar': 'لا توجد دولة مطابقة للبحث.',
    'en': 'No country matches the search.'
  },
  'country_protocol': {
    'ar': 'المراسم والبروتوكول المحلي',
    'en': 'Local ceremonies and protocol'
  },
  'country_titles': {
    'ar': 'الألقاب والمخاطبات',
    'en': 'Titles and forms of address'
  },
  'capital': {'ar': 'العاصمة', 'en': 'Capital'},
  'language': {'ar': 'اللغة الرسمية', 'en': 'Official language'},
  'currency': {'ar': 'العملة', 'en': 'Currency'},
  'timezone': {'ar': 'المنطقة الزمنية', 'en': 'Time zone'},
  'system': {'ar': 'النظام السياسي', 'en': 'Political system'},
  'national_day': {'ar': 'العيد الوطني', 'en': 'National day'},
  // Protocol guide
  'guide_title': {
    'ar': 'دليل البروتوكول الدولي',
    'en': 'International Protocol Guide'
  },
  'guide_empty': {
    'ar': 'تعذّر تحميل أقسام الدليل. تحقق من الاتصال وحاول مرة أخرى.',
    'en': 'The guide sections could not be loaded. Please try again.'
  },
  'section_empty': {
    'ar': 'لا توجد مقالات في هذا القسم بعد.',
    'en': 'No articles in this section yet.'
  },
  // Library
  'library_docs': {
    'ar': 'الوثائق والاتفاقيات الدولية',
    'en': 'International documents and conventions'
  },
  'library_templates': {
    'ar': 'النماذج والقوالب الجاهزة',
    'en': 'Ready-made forms and templates'
  },
  'library_search_hint': {
    'ar': 'ابحث في المكتبة...',
    'en': 'Search the library...'
  },
  'library_no_templates': {
    'ar': 'لا توجد نماذج مطابقة للبحث.',
    'en': 'No templates match the search.'
  },
  'library_note': {
    'ar':
        'ملاحظة: الوثائق الدولية روابط إلى مصادرها الرسمية (الأمم المتحدة وغيرها) ولا تُخزَّن داخل التطبيق احترامًا لحقوق النشر.',
    'en':
        'Note: international documents are links to their official sources (the United Nations and others) and are not stored inside the app, in respect of copyright.'
  },
  'open_link_failed': {
    'ar': 'تعذر فتح الرابط',
    'en': 'Could not open the link'
  },
  'library_load_failed': {
    'ar': 'تعذر تحميل المكتبة، حاول مجددًا',
    'en': 'Could not load the library, please try again'
  },
  // Favorites
  'favorites': {'ar': 'المفضلة', 'en': 'Favorites'},
  'favorites_empty': {
    'ar':
        'لا توجد عناصر مفضلة بعد.\nاضغط على النجمة في أي مقال أو دولة لحفظها هنا.',
    'en':
        'No favorites yet.\nTap the star on any article or country to save it here.'
  },
  'favorites_articles': {'ar': 'مقالات مفضلة', 'en': 'Favorite articles'},
  'favorites_countries': {'ar': 'دول مفضلة', 'en': 'Favorite countries'},
  // Settings
  'settings': {'ar': 'الإعدادات', 'en': 'Settings'},
  'settings_language': {'ar': 'اللغة / Language', 'en': 'Language / اللغة'},
  'settings_font': {'ar': 'حجم الخط', 'en': 'Font size'},
  'settings_notif_days': {
    'ar': 'تذكير بالأعياد الوطنية',
    'en': 'National-day reminders'
  },
  'settings_notif_days_sub': {
    'ar': 'إشعار صباحي في يوم العيد الوطني لكل دولة',
    'en': 'A morning notification on each country’s national day'
  },
  'settings_notif_events': {'ar': 'تذكير بالمناسبات', 'en': 'Event reminders'},
  'settings_notif_events_sub': {
    'ar': 'إشعار صباح يوم المناسبة',
    'en': 'A notification on the morning of the event'
  },
  'settings_dark': {'ar': 'الوضع الليلي', 'en': 'Night mode'},
  'settings_dark_sub': {
    'ar': 'مظهر داكن مريح للعين في الإضاءة الخافتة',
    'en': 'A dark, eye-friendly look for low light'
  },
  'settings_generative': {
    'ar': 'الوضع التوليدي (اختياري)',
    'en': 'Generative mode (optional)'
  },
  'settings_generative_desc': {
    'ar':
        'المساعد الحالي يعمل دون إنترنت من قاعدة المعرفة الموثوقة. لوضع توليدي متقدم مستقبلًا، يمكنك إضافة مفتاح API هنا — يُحفظ على جهازك فقط ولا يُرسل إلا لخدمة الذكاء الاصطناعي التي تختارها، والتطبيق يعمل كاملًا بدونه.',
    'en':
        'The current assistant works offline from the trusted knowledge base. For a future advanced generative mode, you can add an API key here — it is stored on your device only and is sent only to the AI service you choose; the app works fully without it.'
  },
  'settings_api_label': {
    'ar': 'مفتاح API (اختياري)',
    'en': 'API key (optional)'
  },
  'settings_save_key': {'ar': 'حفظ المفتاح', 'en': 'Save key'},
  'settings_key_saved': {
    'ar': 'تم حفظ المفتاح على جهازك',
    'en': 'The key was saved on your device'
  },
  'settings_reschedule': {
    'ar': 'إعادة جدولة التذكيرات',
    'en': 'Reschedule reminders'
  },
  'settings_rescheduled': {
    'ar': 'تمت إعادة جدولة التذكيرات',
    'en': 'Reminders rescheduled'
  },
  // Model (P6) — النموذج المحلي Qwen GGUF عبر fllama_cpp.
  'settings_model': {'ar': 'النموذج المحلي', 'en': 'Local model'},
  'settings_model_desc': {
    'ar':
        'التوليد المحلي يعمل دون إنترنت بعد تنزيل النموذج مرة واحدة عند أول إعداد. يُنزَّل ملف النموذج إلى مجلد مستندات التطبيق فقط — لا داخل التطبيق ولا ضمن ملفاته. عند غياب النموذج أو فشل تحميله يعود المساعد تلقائياً إلى الوضع الاسترجاعي.',
    'en':
        'Local generation works offline after downloading the model once at first setup. The model file is downloaded into the app documents folder only — never inside the app or its assets. If the model is missing or fails to load, the assistant automatically falls back to retrieval mode.'
  },
  'model_status_not_downloaded': {
    'ar': 'غير منزّل',
    'en': 'Not downloaded'
  },
  'model_status_downloaded': {'ar': 'منزّل وجاهز', 'en': 'Downloaded & ready'},
  'model_status_downloading': {'ar': 'جارٍ التنزيل…', 'en': 'Downloading…'},
  'model_status_invalid': {
    'ar': 'ملف غير سليم — أعد التنزيل',
    'en': 'Invalid file — re-download'
  },
  'model_status_verifying': {'ar': 'جارٍ التحقق…', 'en': 'Verifying…'},
  'model_download': {'ar': 'تنزيل النموذج', 'en': 'Download model'},
  'model_cancel_download': {'ar': 'إيقاف التنزيل', 'en': 'Cancel download'},
  'model_delete': {'ar': 'حذف النموذج', 'en': 'Delete model'},
  'model_delete_confirm': {
    'ar': 'سيُحذف ملف النموذج من جهازك، وسيعود المساعد إلى الوضع الاسترجاعي. يمكنك إعادة تنزيله لاحقاً.',
    'en': 'The model file will be deleted from your device and the assistant will return to retrieval mode. You can re-download it later.'
  },
  'model_deleted': {'ar': 'تم حذف النموذج', 'en': 'Model deleted'},
  'model_downloaded_ok': {
    'ar': 'اكتمل التنزيل والتحقق — النموذج جاهز دون إنترنت',
    'en': 'Download and verification complete — the model is ready offline'
  },
  'model_download_cancelled': {
    'ar': 'أُلغي التنزيل — يمكنك الاستئناف لاحقاً من حيث توقفت',
    'en': 'Download cancelled — you can resume later from where it stopped'
  },
  'model_download_failed': {
    'ar': 'تعذّر التنزيل — تحقق من الاتصال وحاول مجدداً',
    'en': 'Download failed — check the connection and try again'
  },
  'model_enable': {'ar': 'تفعيل التوليد المحلي', 'en': 'Enable local generation'},
  'model_requirements': {'ar': 'متطلبات الجهاز', 'en': 'Device requirements'},
  'model_size': {'ar': 'حجم التنزيل', 'en': 'Download size'},
  'model_ram': {'ar': 'الذاكرة الموصى بها', 'en': 'Recommended memory'},
  'model_needs_space': {
    'ar': 'تأكد من توفر مساحة حرة كافية على جهازك قبل التنزيل',
    'en': 'Make sure enough free space is available on your device before downloading'
  },
  'model_sha_unknown': {
    'ar': 'لم يتوفر SHA-256 المتوقع من المصدر — تم التحقق من حجم الملف فقط',
    'en': 'No expected SHA-256 was available from the source — file size was verified only'
  },
  'model_verify': {
    'ar': 'التحقق من سلامة الملف',
    'en': 'Verify file integrity'
  },
  // Academy (§7) — structure follows the book's index (BOOK_INDEX.md:
  // 2 parts, 5 chapters). Lesson titles are chapter/topic titles only;
  // no lesson content is invented or attributed to the book yet.
  'academy_title': {'ar': 'الأكاديمية والتدريب', 'en': 'Academy & Training'},
  'academy_intro': {
    'ar':
        'مستويات تعليمية ودروس منظمة واختبارات وسيناريوهات عملية، مبنية على فصول كتاب «البروتوكول والمراسم».',
    'en':
        'Levels, structured lessons, quizzes and practical scenarios, built on the chapters of «البروتوكول والمراسم».'
  },
  'academy_status': {
    'ar': 'قيد الإعداد — المحتوى من الكتاب بعد اكتمال الاستخراج',
    'en': 'In preparation — content from the book once extraction is complete'
  },
  'academy_level1': {
    'ar': 'المستوى الأول: الأسس النظرية والتاريخية',
    'en': 'Level 1: Theory and history'
  },
  'academy_level1_sub': {
    'ar': 'الباب الأول — الفصلان الأول والثاني',
    'en': 'Part 1 — Chapters 1 and 2'
  },
  'academy_level2': {
    'ar': 'المستوى الثاني: إدارة المراسم الرسمية في الدولة',
    'en': 'Level 2: Managing official ceremonial in the state'
  },
  'academy_level2_sub': {
    'ar': 'الباب الثاني — الفصل الأول',
    'en': 'Part 2 — Chapter 1'
  },
  'academy_level3': {
    'ar': 'المستوى الثالث: الممارسات التطبيقية والدبلوماسية',
    'en': 'Level 3: Practical and diplomatic practice'
  },
  'academy_level3_sub': {
    'ar': 'الباب الثاني — الفصلان الثاني والثالث',
    'en': 'Part 2 — Chapters 2 and 3'
  },
  'academy_lessons': {'ar': 'الدروس', 'en': 'Lessons'},
  'academy_lesson_source': {
    'ar': 'المصدر: كتاب «البروتوكول والمراسم»',
    'en': 'Source: «البروتوكول والمراسم»'
  },
  'academy_lesson_note': {
    'ar':
        'نص الدرس الكامل لم يُستخرج من الكتاب بعد، لذلك لا يُعرض هنا أي محتوى منسوب إليه. عند اكتمال الاستخراج والمراجعة يُفتح الدرس بمحتواه وأسئلته.',
    'en':
        'The full lesson text has not been extracted from the book yet, so no content attributed to it is shown here. Once extraction and review are complete, the lesson will open with its content and questions.'
  },
  'academy_browse_encyclopedia': {
    'ar': 'تصفح موضوعات ذات صلة في الموسوعة',
    'en': 'Browse related topics in the Encyclopedia'
  },
  'academy_quiz_title': {
    'ar': 'الاختبارات والسيناريوهات العملية',
    'en': 'Quizzes and practical scenarios'
  },
  'academy_quiz_body': {
    'ar':
        'أسئلة اختيار من متعدد وسيناريوهات عملية وحالات دراسية وتقييم مستوى، مع شرح المساعد للإجابات وتصحيح الأخطاء التعليمية — تُفعَّل مع نشر أول درس، ويبدأ حينها سجل التقدم.',
    'en':
        'Multiple-choice questions, practical scenarios, case studies and level assessment, with the assistant explaining answers and correcting learning mistakes — enabled when the first lesson is published, when progress tracking starts.'
  },
  'academy_progress': {'ar': 'التقدم', 'en': 'Progress'},
  'academy_progress_none': {
    'ar': 'لا دروس منشورة بعد — 0 من {n}. يبدأ سجل التقدم مع نشر أول درس.',
    'en':
        'No lessons published yet — 0 of {n}. Progress tracking starts when the first lesson is published.'
  },
  // Archives (§4.6) — favorites, saved chats, user documents/plans, activity.
  'archives_title': {'ar': 'المحفوظات', 'en': 'Archives'},
  'archives_chats': {'ar': 'محادثات محفوظة', 'en': 'Saved conversations'},
  'archives_chats_body': {
    'ar':
        'قيد الإعداد — حفظ المحادثات يبدأ مع تطوير المساعد إلى نموذجه اللغوي الكامل؛ المحادثات الحالية لا تُحفظ بعد انتهاء الجلسة.',
    'en':
        'In preparation — saving conversations starts when the assistant grows into its full language model; current conversations are not kept after the session ends.'
  },
  'archives_docs': {'ar': 'مستنداتي وخططي', 'en': 'My documents & plans'},
  'archives_events': {'ar': 'مناسباتي', 'en': 'My events'},
  'archives_plans': {
    'ar': 'مخططات الجلوس المحفوظة',
    'en': 'Saved seating plans'
  },
  'archives_activity': {'ar': 'سجل النشاط', 'en': 'Activity log'},
  'archives_no_activity': {
    'ar': 'لا نشاط محفوظ بعد — اقرأ موضوعاً أو أنشئ مناسبة وستظهر هنا.',
    'en':
        'No saved activity yet — read an article or create an event and it will appear here.'
  },
  // About & Contact (§1) — contact details appear ONLY on this page.
  'about': {'ar': 'عن التطبيق والتواصل', 'en': 'About & Contact'},
  'about_title': {
    'ar': 'عن البروتوكول والمراسم',
    'en': 'About PROTOCOL & CEREMONIAL'
  },
  'about_contact': {'ar': 'التواصل', 'en': 'Contact'},
  'about_email_label': {'ar': 'البريد الإلكتروني', 'en': 'Email'},
  'about_phone_label': {'ar': 'رقم التواصل', 'en': 'Contact number'},
  'about_github_label': {'ar': 'حساب GitHub', 'en': 'GitHub account'},
  'about_owner': {'ar': 'صاحب التطبيق', 'en': 'App owner'},
  'about_owner_name': {'ar': 'أسعد منصور', 'en': 'Asaad Mansour'},
  'about_dev': {
    'ar': 'برمجة وتصميم',
    'en': 'Programming & design'
  },
  'about_dev_name': {'ar': 'عز الدين منصور', 'en': 'Ezzaldeen Mansour'},
  'about_goals': {'ar': 'أهداف التطبيق', 'en': 'App goals'},
  'about_goals_body': {
    'ar':
        'مرجع رقمي متكامل في البروتوكول والمراسم يخدم طلاب العلوم السياسية والعلاقات الدولية والباحثين والدبلوماسيين وموظفي المراسم ومنظمي المؤتمرات والفعاليات الرسمية، ويحوّل النظرية إلى معرفة عملية قابلة للاستخدام: موسوعة تفاعلية وأكاديمية تدريبية ومساعد ذكي وأدوات عمل احترافية.',
    'en':
        'An integrated digital reference for protocol and ceremonial serving students of political science and international relations, researchers, diplomats, ceremonial staff and organizers of conferences and official events, turning theory into usable practical knowledge: an interactive encyclopedia, a training academy, a smart assistant and professional work tools.'
  },
  'about_rights': {
    'ar': 'حقوق الملكية والتطوير',
    'en': 'Ownership & development rights'
  },
  'about_rights_body': {
    'ar':
        'المحتوى والمرجعية: الباحث أسعد منصور. البرمجة والتصميم والتطوير: عز الدين منصور. جميع الحقوق محفوظة © 2026.',
    'en':
        'Content and reference: Researcher Asaad Mansour. Programming, design and development: Ezzaldeen Mansour. All rights reserved © 2026.'
  },
  'about_privacy_title': {'ar': 'سياسة الخصوصية', 'en': 'Privacy policy'},
  'about_privacy_body': {
    'ar':
        'يعمل التطبيق دون إنترنت في وظائفه المحلية، ويحفظ بياناتك (الإعدادات والمفضلة والمناسبات والمخططات) على جهازك فقط في قاعدة بيانات محلية، ولا يجمع بيانات شخصية ولا يرسلها إلى أي خادم. مفتاح API الاختياري — إن أدخلته — يُحفظ على جهازك فقط. الروابط الخارجية (وثائق المكتبة) تُفتح في المتصفح فقط عندما تضغط عليها.',
    'en':
        'The app works offline in its local functions and keeps your data (settings, favorites, events and plans) on your device only, in a local database; it collects no personal data and sends none to any server. The optional API key — if you enter one — is stored on your device only. External links (library documents) open in the browser only when you tap them.'
  },
  'about_terms_title': {'ar': 'شروط الاستخدام', 'en': 'Terms of use'},
  'about_terms_body': {
    'ar':
        'المحتوى مرجع تعليمي وعملي، ولا يمثّل استشارة قانونية ولا موقفاً رسمياً لأي جهة. القواعد المنسوبة إلى اتفاقيات تُعرض بمصادرها، وما عداها ممارسات وأعراف موضحة بصفتها. راجِع الجهة الرسمية المختصة قبل الاعتماد على أي ترتيب في مناسبة رسمية. لا يجوز تقديم التطبيق على أنه صادر عن الأمم المتحدة أو أي حكومة أو مؤسسة دولية.',
    'en':
        'The content is an educational and practical reference; it is not legal advice and does not represent the official position of any body. Rules attributed to conventions are shown with their sources; the rest are practices and customs identified as such. Consult the competent official authority before relying on any arrangement at an official event. The app must not be presented as issued by the United Nations, any government, or any international institution.'
  },
  'about_desc': {
    'ar':
        'منصة معرفية وتقنية متخصصة في البروتوكول الدولي والمراسم الدبلوماسية. يعمل التطبيق دون إنترنت في معظم وظائفه، ويعتمد في مصادره على وثائق دولية منشورة موثقة، ويُعرض مصدر كل مادة معها.',
    'en':
        'A knowledge and practical platform for international protocol and diplomatic ceremonial. Most of the app works offline. Its sources are published, documented international documents, and the source of each item is shown with it.'
  },
  'about_disclaimer': {
    'ar':
        'هذا التطبيق مرجع تعليمي وعملي، ولا يدّعي أي تبعية للأمم المتحدة أو أي حكومة أو مؤسسة دولية، ولا يمثّل أي جهة رسمية.',
    'en':
        'This app is an educational and practical reference. It claims no affiliation with the United Nations, any government, or any international institution, and it does not represent any official body.'
  },
  // Common
  'save': {'ar': 'حفظ', 'en': 'Save'},
  'cancel': {'ar': 'إلغاء', 'en': 'Cancel'},
  'delete': {'ar': 'حذف', 'en': 'Delete'},
  'confirm': {'ar': 'تأكيد', 'en': 'Confirm'},
  'retry': {'ar': 'إعادة المحاولة', 'en': 'Retry'},
  'close': {'ar': 'إغلاق', 'en': 'Close'},
  'share': {'ar': 'مشاركة', 'en': 'Share'},
  'source': {'ar': 'المصدر:', 'en': 'Source:'},
  'last_review': {'ar': 'آخر مراجعة:', 'en': 'Last reviewed:'},
  'error_generic': {
    'ar': 'حدث خطأ. حاول مرة أخرى.',
    'en': 'Something went wrong. Please try again.'
  },
  'field_required': {'ar': 'هذا الحقل مطلوب', 'en': 'This field is required'},
  // Tools hub
  'tools_title': {'ar': 'الأدوات العملية', 'en': 'Practical Tools'},
  'tool_precedence': {'ar': 'حاسبة الأسبقية', 'en': 'Precedence Calculator'},
  'tool_precedence_sub': {
    'ar': 'رتّب الشخصيات وفق قواعد الأسبقية الدبلوماسية',
    'en': 'Order people by diplomatic precedence rules'
  },
  'tool_seating': {'ar': 'مخطط الجلوس', 'en': 'Seating Planner'},
  'tool_seating_sub': {
    'ar': 'طاولة مستديرة أو مستطيلة أو على شكل U',
    'en': 'Round, rectangular, or U-shaped table'
  },
  'tool_events': {'ar': 'منظم المناسبات', 'en': 'Event Organizer'},
  'tool_events_sub': {
    'ar': 'أنشئ مناسبة بضيوفها وبرنامجها وقوائمها',
    'en': 'Create an event with its guests, program, and checklists'
  },
  'tool_docs': {'ar': 'مولد المستندات', 'en': 'Document Generator'},
  'tool_docs_sub': {
    'ar': 'دعوات وخطابات وبرامج — تصدير PDF',
    'en': 'Invitations, letters, programs — PDF export'
  },
  'tool_checker': {'ar': 'مدقق البروتوكول', 'en': 'Protocol Checker'},
  'tool_checker_sub': {
    'ar': 'راجع خطة مناسبة واكتشف الأخطاء',
    'en': 'Review an event plan and spot mistakes'
  },
  // Precedence calculator
  'prec_intro': {
    'ar':
        'أضف الشخصيات (الاسم والمنصب والدولة وتاريخ تقديم أوراق الاعتماد للسفراء)، ثم اضغط «احسب الترتيب».',
    'en':
        'Add people (name, post, country, and credential date for ambassadors), then tap “Calculate order”.'
  },
  'prec_name_post': {'ar': 'الاسم / المنصب', 'en': 'Name / Post'},
  'prec_category': {'ar': 'الفئة', 'en': 'Category'},
  'prec_country': {'ar': 'الدولة', 'en': 'Country'},
  'prec_cred_date': {
    'ar': 'تاريخ تقديم أوراق الاعتماد (YYYY-MM-DD)',
    'en': 'Credential presentation date (YYYY-MM-DD)'
  },
  'prec_add_person': {'ar': 'إضافة شخص', 'en': 'Add person'},
  'prec_compute': {'ar': 'احسب الترتيب', 'en': 'Calculate order'},
  'prec_result': {'ar': 'الترتيب المقترح', 'en': 'Suggested order'},
  'prec_share': {'ar': 'مشاركة الترتيب', 'en': 'Share the order'},
  'prec_need_one': {
    'ar': 'أضف شخصًا واحدًا على الأقل مع الاسم أولًا',
    'en': 'Add at least one person with a name first'
  },
  'prec_bad_date': {
    'ar': 'تاريخ اعتماد غير صحيح لـ «{name}»: استخدم الصيغة YYYY-MM-DD',
    'en': 'Invalid credential date for “{name}”: use the format YYYY-MM-DD'
  },
  'prec_ignored': {
    'ar': 'تم تجاهل {n} بلا اسم',
    'en': 'Ignored {n} without a name'
  },
  'prec_share_fail': {
    'ar': 'تعذرت المشاركة، حاول مجددًا',
    'en': 'Sharing failed, please try again'
  },
  'prec_rule_text': {
    'ar':
        'القاعدة: يتقدم رؤساء البعثات في فئتهم بحسب تاريخ وساعة تولي مهامهم (المادة 16)، ويُحدَّد تاريخ التولي بتقديم أوراق الاعتماد (المادة 13). أما ترتيب الفئات فيتبع المادة 14.',
    'en':
        'Rule: heads of mission take precedence within their class by the date and time they took up their functions (Article 16); the date of taking up functions is set by presenting credentials (Article 13). The order of classes follows Article 14.'
  },
  'prec_accred': {'ar': 'اعتماد:', 'en': 'Credentials:'},
  // Seating
  'seat_new': {'ar': 'مخطط جديد', 'en': 'New plan'},
  'seat_empty': {
    'ar':
        'لا توجد مخططات محفوظة بعد.\nأنشئ مخططًا لمائدة مستديرة أو مستطيلة أو على شكل U.',
    'en':
        'No saved plans yet.\nCreate a plan for a round, rectangular, or U-shaped table.'
  },
  'seat_delete_title': {'ar': 'حذف المخطط', 'en': 'Delete plan'},
  'seat_delete_body': {
    'ar': 'سيتم حذف مخطط «{name}» نهائيًا.',
    'en': 'Plan “{name}” will be permanently deleted.'
  },
  'seat_delete_fail': {
    'ar': 'تعذر حذف المخطط، حاول مجددًا',
    'en': 'Could not delete the plan, please try again'
  },
  'seat_seats': {'ar': 'مقاعد', 'en': 'seats'},
  'seat_name': {'ar': 'اسم المخطط', 'en': 'Plan name'},
  'seat_shape': {'ar': 'شكل المائدة', 'en': 'Table shape'},
  'seat_seats_label': {'ar': 'المقاعد:', 'en': 'Seats:'},
  'seat_table': {'ar': 'المائدة', 'en': 'Table'},
  'seat_table_rect': {'ar': 'المائدة المستطيلة', 'en': 'Rectangular table'},
  'seat_table_u': {'ar': 'المائدة (شكل U)', 'en': 'U-shaped table'},
  'seat_no_guests': {
    'ar': 'لا يوجد ضيوف بعد — أضف ضيوفًا لعرضهم على المائدة.',
    'en': 'No guests yet — add guests to show them at the table.'
  },
  'seat_auto': {
    'ar': 'ترتيب تلقائي حسب الأسبقية',
    'en': 'Auto-arrange by precedence'
  },
  'seat_add_guest': {'ar': 'إضافة ضيف', 'en': 'Add guest'},
  'seat_guest_name': {'ar': 'اسم الضيف', 'en': 'Guest name'},
  'seat_arranged': {
    'ar': 'تم الترتيب حسب الأسبقية الدبلوماسية',
    'en': 'Arranged by diplomatic precedence'
  },
  'seat_need_name': {
    'ar': 'أدخل اسمًا للمخطط أولًا',
    'en': 'Enter a plan name first'
  },
  'seat_ignored': {
    'ar': 'تم تجاهل {n} بلا اسم',
    'en': 'Ignored {n} without a name'
  },
  'seat_too_many': {
    'ar':
        'عدد الضيوف ({n}) يتجاوز عدد المقاعد ({seats}) — ستظهر أول {seats} فقط على المائدة',
    'en':
        'Guests ({n}) exceed the seats ({seats}) — only the first {seats} will appear at the table'
  },
  'seat_save_fail': {
    'ar': 'تعذر حفظ المخطط، حاول مجددًا',
    'en': 'Could not save the plan, please try again'
  },
  'seat_saved': {'ar': 'تم حفظ المخطط', 'en': 'Plan saved'},
  'shape_round': {'ar': 'مستديرة', 'en': 'Round'},
  'shape_rect': {'ar': 'مستطيلة', 'en': 'Rectangular'},
  'shape_u': {'ar': 'U', 'en': 'U'},
  // Events
  'events_title': {'ar': 'منظم المناسبات', 'en': 'Event Organizer'},
  'event_new': {'ar': 'مناسبة جديدة', 'en': 'New event'},
  'event_title_label': {'ar': 'اسم المناسبة', 'en': 'Event name'},
  'event_type': {'ar': 'نوع المناسبة', 'en': 'Event type'},
  'event_place': {'ar': 'المكان', 'en': 'Place'},
  'event_date': {'ar': 'التاريخ:', 'en': 'Date:'},
  'event_guests_expected': {
    'ar': 'عدد الضيوف المتوقع:',
    'en': 'Expected guests:'
  },
  'event_create': {'ar': 'إنشاء', 'en': 'Create'},
  'event_need_title': {'ar': 'أدخل اسم المناسبة', 'en': 'Enter the event name'},
  'event_need_place': {
    'ar': 'أدخل مكان المناسبة',
    'en': 'Enter the event place'
  },
  'event_empty': {
    'ar':
        'لا توجد مناسبات بعد.\nأنشئ مناسبة وسيُنشأ لها برنامج وقائمة تحقق وتذكير تلقائيًا.',
    'en':
        'No events yet.\nCreate an event and a program, checklist, and reminder will be generated automatically.'
  },
  'event_delete_title': {'ar': 'حذف المناسبة', 'en': 'Delete event'},
  'event_delete_body': {
    'ar': 'سيتم حذف مناسبة «{name}» مع ضيوفها وبرنامجها وقائمة التحقق نهائيًا.',
    'en':
        'Event “{name}” will be permanently deleted with its guests, program, and checklist.'
  },
  'event_delete_fail': {
    'ar': 'تعذر حذف المناسبة، حاول مجددًا',
    'en': 'Could not delete the event, please try again'
  },
  'event_type_visit': {'ar': 'زيارة رسمية', 'en': 'Official visit'},
  'event_type_conference': {'ar': 'مؤتمر', 'en': 'Conference'},
  'event_type_celebration': {'ar': 'احتفال', 'en': 'Celebration'},
  'event_type_bilateral': {'ar': 'اجتماع ثنائي', 'en': 'Bilateral meeting'},
  'event_type_banquet': {'ar': 'مأدبة رسمية', 'en': 'Official banquet'},
  // Event detail
  'event_detail_title': {'ar': 'المناسبة', 'en': 'Event'},
  'tab_guests': {'ar': 'الضيوف', 'en': 'Guests'},
  'tab_program': {'ar': 'البرنامج', 'en': 'Program'},
  'tab_checklist': {'ar': 'قائمة التحقق', 'en': 'Checklist'},
  'event_check_protocol': {'ar': 'تدقيق البروتوكول', 'en': 'Check protocol'},
  'guests_count': {'ar': 'الضيوف ({n})', 'en': 'Guests ({n})'},
  'guests_empty': {'ar': 'لا يوجد ضيوف بعد.', 'en': 'No guests yet.'},
  'program_title': {'ar': 'برنامج المناسبة', 'en': 'Event program'},
  'program_add': {'ar': 'إضافة فقرة', 'en': 'Add item'},
  'program_empty': {'ar': 'لا توجد فقرات بعد.', 'en': 'No items yet.'},
  'checklist_count': {
    'ar': 'قائمة التحقق ({done}/{total})',
    'en': 'Checklist ({done}/{total})'
  },
  'checklist_add': {'ar': 'إضافة بند', 'en': 'Add item'},
  'checklist_empty': {'ar': 'لا توجد بنود بعد.', 'en': 'No items yet.'},
  'guest_add_title': {'ar': 'إضافة ضيف', 'en': 'Add guest'},
  'guest_need_name': {'ar': 'أدخل اسم الضيف', 'en': 'Enter the guest name'},
  'guest_add': {'ar': 'إضافة', 'en': 'Add'},
  'program_add_title': {'ar': 'إضافة فقرة للبرنامج', 'en': 'Add program item'},
  'program_time': {'ar': 'الوقت', 'en': 'Time'},
  'program_item_title': {'ar': 'عنوان الفقرة', 'en': 'Item title'},
  'program_need_time': {'ar': 'أدخل الوقت', 'en': 'Enter the time'},
  'program_time_format': {
    'ar': 'استخدم الصيغة HH:MM مثل 10:00',
    'en': 'Use the format HH:MM, e.g. 10:00'
  },
  'program_need_title': {
    'ar': 'أدخل عنوان الفقرة',
    'en': 'Enter the item title'
  },
  'checklist_add_title': {
    'ar': 'إضافة بند لقائمة التحقق',
    'en': 'Add checklist item'
  },
  'checklist_item': {'ar': 'البند', 'en': 'Item'},
  'checklist_need_text': {'ar': 'أدخل نص البند', 'en': 'Enter the item text'},
  // Document generator
  'docs_title': {'ar': 'مولد المستندات', 'en': 'Document Generator'},
  'docs_empty': {'ar': 'لا توجد نماذج متاحة.', 'en': 'No templates available.'},
  'docs_choose': {'ar': 'اختر النموذج', 'en': 'Choose a template'},
  'docs_preview': {'ar': 'المعاينة', 'en': 'Preview'},
  'docs_export_pdf': {'ar': 'تصدير PDF', 'en': 'Export PDF'},
  'docs_copy': {'ar': 'نسخ النص', 'en': 'Copy text'},
  'docs_share': {'ar': 'مشاركة', 'en': 'Share'},
  'docs_docx_note': {
    'ar':
        'ملاحظة: تصدير DOCX غير متوفر في هذه النسخة (سيُضاف لاحقًا) — التصدير المتاح هو PDF.',
    'en':
        'Note: DOCX export is not available in this version (coming later) — PDF export is available.'
  },
  'docs_missing_export': {
    'ar': 'أكمل الحقول التالية قبل التصدير: {fields}',
    'en': 'Complete the following fields before exporting: {fields}'
  },
  'docs_missing_copy': {
    'ar': 'أكمل الحقول التالية قبل النسخ: {fields}',
    'en': 'Complete the following fields before copying: {fields}'
  },
  'docs_missing_share': {
    'ar': 'أكمل الحقول التالية قبل المشاركة: {fields}',
    'en': 'Complete the following fields before sharing: {fields}'
  },
  'docs_copied': {'ar': 'تم نسخ النص', 'en': 'Text copied'},
  'docs_pdf_fail': {
    'ar': 'تعذر إنشاء ملف PDF أو مشاركته، حاول مجددًا',
    'en': 'Could not create or share the PDF, please try again'
  },
  'docs_share_fail': {
    'ar': 'تعذرت المشاركة، حاول مجددًا',
    'en': 'Sharing failed, please try again'
  },
  // Protocol checker
  'checker_empty': {
    'ar':
        'لا توجد مناسبات محفوظة لتدقيقها.\nأنشئ مناسبة أولًا من منظم المناسبات.',
    'en':
        'No saved events to check.\nCreate an event first in the event organizer.'
  },
  'checker_result': {'ar': 'نتيجة التدقيق', 'en': 'Check result'},
  'checker_not_found': {
    'ar': 'المناسبة غير موجودة أو حُذفت.',
    'en': 'The event does not exist or was deleted.'
  },
  'checker_clean': {
    'ar': 'لا توجد مشاكل.\nخطة المناسبة سليمة وفق القواعد التي تم فحصها.',
    'en': 'No issues.\nThe event plan is sound under the rules checked.'
  },
  'checker_found': {
    'ar': 'تم العثور على {n} ملاحظات في خطة «{name}»:',
    'en': 'Found {n} notes in the plan for “{name}”:'
  },
  'sev_error': {'ar': 'خطأ', 'en': 'Error'},
  'sev_warning': {'ar': 'تنبيه', 'en': 'Warning'},
  'chk_no_program': {
    'ar': 'لا يوجد برنامج للمناسبة',
    'en': 'No program for the event'
  },
  'chk_no_program_detail': {
    'ar': 'المناسبة بلا أي فقرات في برنامجها.',
    'en': 'The event has no items in its program.'
  },
  'chk_no_program_rule': {
    'ar': 'برنامج الزيارة أو المناسبة عنصر أساسي في التحضير البروتوكولي.',
    'en': 'A visit or event program is a core element of protocol preparation.'
  },
  'chk_no_program_rec': {
    'ar':
        'أضف فقرات البرنامج من صفحة المناسبة: الاستقبال، الاجتماعات، الفعاليات، المغادرة.',
    'en':
        'Add program items from the event page: reception, meetings, activities, departure.'
  },
  'chk_no_reception': {
    'ar': 'البرنامج بلا فقرة استقبال',
    'en': 'Program has no reception item'
  },
  'chk_no_reception_detail': {
    'ar': 'لم نعثر على فقرة استقبال في البرنامج.',
    'en': 'No reception item was found in the program.'
  },
  'chk_no_reception_rule': {
    'ar': 'مراسم الاستقبال أول عناصر برنامج أي وفد رسمي.',
    'en':
        'Reception ceremonies are the first element of any official delegation program.'
  },
  'chk_no_reception_rec': {
    'ar': 'أضف فقرة «استقبال الوفد» في بداية البرنامج مع المكان والوقت.',
    'en':
        'Add a “Reception of the delegation” item at the start of the program, with place and time.'
  },
  'chk_no_rank': {
    'ar': 'ضيوف بلا فئة أسبقية',
    'en': 'Guests without a precedence category'
  },
  'chk_no_rank_detail': {
    'ar': '{n} من الضيوف بلا فئة منصب محددة، فلا يمكن ترتيبهم.',
    'en': '{n} guests have no post category set, so they cannot be ordered.'
  },
  'chk_no_rank_rule': {
    'ar': 'تحديد فئة كل ضيف شرط لترتيب الأسبقية والجلوس.',
    'en':
        'Setting each guest’s category is required to order precedence and seating.'
  },
  'chk_no_rank_rec': {
    'ar': 'حدد فئة المنصب لكل ضيف من قائمة الضيوف.',
    'en': 'Set the post category for each guest in the guest list.'
  },
  'chk_not_ordered': {
    'ar': 'قائمة الضيوف ليست مرتبة حسب الأسبقية',
    'en': 'Guest list is not ordered by precedence'
  },
  'chk_not_ordered_detail': {
    'ar': 'ترتيب الضيوف الحالي يخالف قواعد الأسبقية.',
    'en': 'The current guest order violates the precedence rules.'
  },
  'chk_not_ordered_rule': {
    'ar': 'يتقدم رؤساء البعثات في فئتهم بحسب تاريخ وساعة تولي مهامهم.',
    'en':
        'Heads of mission take precedence within their class by the date and time they took up their functions.'
  },
  'chk_not_ordered_rec': {
    'ar':
        'أعد ترتيب الضيوف حسب الأسبقية (يمكنك استخدام الترتيب التلقائي في مخطط الجلوس).',
    'en':
        'Reorder the guests by precedence (you can use the auto-arrange in the seating planner).'
  },
  'chk_nat_day': {
    'ar': 'تاريخ المناسبة يوافق العيد الوطني لدولة ضيف',
    'en': 'Event date coincides with a guest country’s national day'
  },
  'chk_nat_day_detail': {
    'ar': 'يوم {date} يوافق {name} ({country}).',
    'en': '{date} coincides with {name} ({country}).'
  },
  'chk_nat_day_rule': {
    'ar': 'مراعاة الأعياد الوطنية للضيوف من قواعد الإتيكيت الدبلوماسي.',
    'en': 'Respecting guests’ national days is part of diplomatic etiquette.'
  },
  'chk_nat_day_rec': {
    'ar':
        'راعِ المناسبة في البرنامج (تهنئة رسمية) أو أعد جدولة التاريخ إن أمكن.',
    'en':
        'Acknowledge the occasion in the program (a formal greeting) or reschedule the date if possible.'
  },
  'chk_no_speeches': {
    'ar': 'مأدبة رسمية بلا فقرة كلمات أو أنخاب',
    'en': 'Official banquet with no speeches or toasts'
  },
  'chk_no_speeches_detail': {
    'ar': 'لا توجد فقرة كلمة أو نخب في برنامج المأدبة.',
    'en': 'No speech or toast item is in the banquet program.'
  },
  'chk_no_speeches_rule': {
    'ar': 'الكلمات والأنخاب جزء معتاد من برنامج المآدب الرسمية.',
    'en':
        'Speeches and toasts are a customary part of official banquet programs.'
  },
  'chk_no_speeches_rec': {
    'ar': 'أضف فقرة «كلمة ترحيبية وأنخاب» إلى البرنامج.',
    'en': 'Add a “Welcome speech and toasts” item to the program.'
  },
  'chk_checklist': {
    'ar': 'قائمة التحقق غير مكتملة',
    'en': 'Checklist incomplete'
  },
  'chk_checklist_detail': {
    'ar': 'بقي {n} من {total} بنود غير منجزة.',
    'en': '{n} of {total} items are still not done.'
  },
  'chk_checklist_rule': {
    'ar': 'استكمال قائمة التحقق قبل المناسبة من أساسيات التنظيم.',
    'en':
        'Completing the checklist before the event is a basic of organization.'
  },
  'chk_checklist_rec': {
    'ar': 'راجع قائمة التحقق من صفحة المناسبة وأكمل البنود المتبقية.',
    'en':
        'Review the checklist on the event page and complete the remaining items.'
  },
  'chk_rule_prefix': {'ar': 'القاعدة:', 'en': 'Rule:'},
  'chk_source_prefix': {'ar': 'المصدر:', 'en': 'Source:'},
  'chk_rec_prefix': {'ar': 'التوصية:', 'en': 'Recommendation:'},
  // Tools hub — the four new standalone tools (V2_PLAN §1.2)
  'tool_delegations': {'ar': 'إدارة الوفود', 'en': 'Delegation Manager'},
  'tool_delegations_sub': {
    'ar': 'وفود بأعضائها ومناصبها وبياناتها وقوائمها',
    'en': 'Delegations with members, posts, details, and lists'
  },
  'tool_visits': {'ar': 'الزيارات الدبلوماسية', 'en': 'Diplomatic Visits'},
  'tool_visits_sub': {
    'ar': 'استقبال وتوديع وزيارات ميدانية وتنقلات',
    'en': 'Reception, farewell, field visits, and transport'
  },
  'tool_conferences': {'ar': 'تنظيم المؤتمرات', 'en': 'Conference Organizer'},
  'tool_conferences_sub': {
    'ar': 'جلسات افتتاح وعمل واختتام ووفود مشاركة',
    'en': 'Opening, working, and closing sessions with delegations'
  },
  'tool_banquets': {'ar': 'المآدب الرسمية', 'en': 'Official Banquets'},
  'tool_banquets_sub': {
    'ar': 'دعوات ومقاعد طاولة شرف وتسلسل فقرات',
    'en': 'Invitations, head-table seats, and program sequence'
  },
  // Delegations
  'del_empty': {
    'ar': 'لا توجد وفود محفوظة بعد.\nأنشئ وفدًا بأعضائه ومناصبهم.',
    'en': 'No saved delegations yet.\nCreate a delegation with its members.'
  },
  'del_new': {'ar': 'وفد جديد', 'en': 'New delegation'},
  'del_name': {'ar': 'اسم الوفد', 'en': 'Delegation name'},
  'del_country': {'ar': 'الدولة', 'en': 'Country'},
  'del_head_name': {'ar': 'اسم رئيس الوفد', 'en': 'Head of delegation'},
  'del_head_title': {'ar': 'منصب رئيس الوفد', 'en': 'Head’s post'},
  'del_notes': {'ar': 'ملاحظات', 'en': 'Notes'},
  'del_members': {'ar': 'الأعضاء', 'en': 'Members'},
  'del_add_member': {'ar': 'إضافة عضو', 'en': 'Add member'},
  'del_member_name': {'ar': 'اسم العضو', 'en': 'Member name'},
  'del_member_title': {'ar': 'المنصب', 'en': 'Post'},
  'del_member_phone': {'ar': 'الهاتف', 'en': 'Phone'},
  'del_member_email': {'ar': 'البريد الإلكتروني', 'en': 'Email'},
  'del_no_members': {
    'ar': 'لا يوجد أعضاء بعد — أضف أعضاء الوفد بمناصبهم.',
    'en': 'No members yet — add the delegation members with their posts.'
  },
  'del_members_count': {
    'ar': '{n} أعضاء',
    'en': '{n} members'
  },
  'del_link_visit': {'ar': 'مرتبط بزيارة', 'en': 'Linked visit'},
  'del_link_conference': {'ar': 'مرتبط بمؤتمر', 'en': 'Linked conference'},
  'del_none': {'ar': 'بلا ارتباط', 'en': 'None'},
  'del_delete_title': {'ar': 'حذف الوفد', 'en': 'Delete delegation'},
  'del_delete_body': {
    'ar': 'سيتم حذف وفد «{name}» وأعضائه نهائيًا.',
    'en': 'Delegation “{name}” and its members will be permanently deleted.'
  },
  'del_delete_fail': {
    'ar': 'تعذر حذف الوفد، حاول مجددًا',
    'en': 'Could not delete the delegation, please try again'
  },
  'del_save_fail': {
    'ar': 'تعذر حفظ الوفد، حاول مجددًا',
    'en': 'Could not save the delegation, please try again'
  },
  'del_saved': {'ar': 'تم حفظ الوفد', 'en': 'Delegation saved'},
  'del_need_name': {
    'ar': 'أدخل اسمًا للوفد أولًا',
    'en': 'Enter a delegation name first'
  },
  'del_member_need_name': {
    'ar': 'أدخل اسم العضو',
    'en': 'Enter the member name'
  },
  'del_export_pdf': {'ar': 'تصدير قائمة الوفد PDF', 'en': 'Export list as PDF'},
  'del_export_fail': {
    'ar': 'تعذر إنشاء ملف PDF أو مشاركته، حاول مجددًا',
    'en': 'Could not create or share the PDF, please try again'
  },
  // Visits
  'visit_empty': {
    'ar': 'لا توجد زيارات محفوظة بعد.\nأنشئ زيارة دبلوماسية ببرنامجها.',
    'en': 'No saved visits yet.\nCreate a diplomatic visit with its program.'
  },
  'visit_new': {'ar': 'زيارة جديدة', 'en': 'New visit'},
  'visit_title_label': {'ar': 'عنوان الزيارة', 'en': 'Visit title'},
  'visit_sending': {'ar': 'الدولة المرسِلة', 'en': 'Sending country'},
  'visit_host': {'ar': 'الدولة المستضيفة', 'en': 'Host country'},
  'visit_head': {'ar': 'رئيس الوفد الزائر', 'en': 'Visiting head of delegation'},
  'visit_arrival': {'ar': 'الوصول', 'en': 'Arrival'},
  'visit_departure': {'ar': 'المغادرة', 'en': 'Departure'},
  'visit_date': {'ar': 'التاريخ', 'en': 'Date'},
  'visit_time': {'ar': 'الوقت', 'en': 'Time'},
  'visit_place': {'ar': 'المكان', 'en': 'Place'},
  'visit_stages': {'ar': 'مراحل الزيارة وبرنامجها', 'en': 'Visit stages & program'},
  'visit_add_stage': {'ar': 'إضافة مرحلة', 'en': 'Add stage'},
  'visit_stage_title': {'ar': 'عنوان المرحلة', 'en': 'Stage title'},
  'visit_stage_kind': {'ar': 'نوع المرحلة', 'en': 'Stage type'},
  'visit_stage_reception': {'ar': 'استقبال', 'en': 'Reception'},
  'visit_stage_farewell': {'ar': 'توديع', 'en': 'Farewell'},
  'visit_stage_meeting': {'ar': 'اجتماع / مباحثات', 'en': 'Meeting / talks'},
  'visit_stage_field': {'ar': 'زيارة ميدانية', 'en': 'Field visit'},
  'visit_stage_transport': {'ar': 'تنقل / موكب', 'en': 'Transport / motorcade'},
  'visit_stage_other': {'ar': 'أخرى', 'en': 'Other'},
  'visit_no_stages': {
    'ar': 'لا توجد مراحل بعد — أضف الاستقبال والتوديع والاجتماعات والزيارات الميدانية.',
    'en': 'No stages yet — add reception, farewell, meetings, and field visits.'
  },
  'visit_linked_delegation': {'ar': 'الوفد الزائر', 'en': 'Visiting delegation'},
  'visit_delete_title': {'ar': 'حذف الزيارة', 'en': 'Delete visit'},
  'visit_delete_body': {
    'ar': 'سيتم حذف زيارة «{name}» وبرنامجها نهائيًا.',
    'en': 'Visit “{name}” and its program will be permanently deleted.'
  },
  'visit_delete_fail': {
    'ar': 'تعذرت حذف الزيارة، حاول مجددًا',
    'en': 'Could not delete the visit, please try again'
  },
  'visit_save_fail': {
    'ar': 'تعذر حفظ الزيارة، حاول مجددًا',
    'en': 'Could not save the visit, please try again'
  },
  'visit_saved': {'ar': 'تم حفظ الزيارة', 'en': 'Visit saved'},
  'visit_need_title': {
    'ar': 'أدخل عنوانًا للزيارة أولًا',
    'en': 'Enter a visit title first'
  },
  // Conferences
  'conf_empty': {
    'ar': 'لا توجد مؤتمرات محفوظة بعد.\nأنشئ مؤتمرًا بجلساته ووفوده.',
    'en': 'No saved conferences yet.\nCreate a conference with sessions and delegations.'
  },
  'conf_new': {'ar': 'مؤتمر جديد', 'en': 'New conference'},
  'conf_title_label': {'ar': 'عنوان المؤتمر', 'en': 'Conference title'},
  'conf_place': {'ar': 'المكان', 'en': 'Place'},
  'conf_start': {'ar': 'تاريخ البدء', 'en': 'Start date'},
  'conf_end': {'ar': 'تاريخ الانتهاء', 'en': 'End date'},
  'conf_sessions': {'ar': 'الجلسات', 'en': 'Sessions'},
  'conf_add_session': {'ar': 'إضافة جلسة', 'en': 'Add session'},
  'conf_session_title': {'ar': 'عنوان الجلسة', 'en': 'Session title'},
  'conf_session_kind': {'ar': 'نوع الجلسة', 'en': 'Session type'},
  'conf_kind_opening': {'ar': 'جلسة افتتاح', 'en': 'Opening session'},
  'conf_kind_working': {'ar': 'جلسة عمل', 'en': 'Working session'},
  'conf_kind_closing': {'ar': 'جلسة اختتام', 'en': 'Closing session'},
  'conf_kind_other': {'ar': 'أخرى', 'en': 'Other'},
  'conf_no_sessions': {
    'ar': 'لا توجد جلسات بعد — أضف جلسة الافتتاح وجلسات العمل والاختتام.',
    'en': 'No sessions yet — add the opening, working, and closing sessions.'
  },
  'conf_delegations': {'ar': 'الوفود المشاركة', 'en': 'Participating delegations'},
  'conf_add_delegation': {'ar': 'إضافة وفد مشارك', 'en': 'Add participating delegation'},
  'conf_no_delegations': {
    'ar': 'لا توجد وفود مشاركة بعد.',
    'en': 'No participating delegations yet.'
  },
  'conf_delete_title': {'ar': 'حذف المؤتمر', 'en': 'Delete conference'},
  'conf_delete_body': {
    'ar': 'سيتم حذف مؤتمر «{name}» وجلساته نهائيًا.',
    'en': 'Conference “{name}” and its sessions will be permanently deleted.'
  },
  'conf_delete_fail': {
    'ar': 'تعذر حذف المؤتمر، حاول مجددًا',
    'en': 'Could not delete the conference, please try again'
  },
  'conf_save_fail': {
    'ar': 'تعذر حفظ المؤتمر، حاول مجددًا',
    'en': 'Could not save the conference, please try again'
  },
  'conf_saved': {'ar': 'تم حفظ المؤتمر', 'en': 'Conference saved'},
  'conf_need_title': {
    'ar': 'أدخل عنوانًا للمؤتمر أولًا',
    'en': 'Enter a conference title first'
  },
  // Banquets
  'banq_empty': {
    'ar': 'لا توجد مآدب محفوظة بعد.\nأنشئ مأدبة بدعواتها وفقراتها.',
    'en': 'No saved banquets yet.\nCreate a banquet with its invitations and program.'
  },
  'banq_new': {'ar': 'مأدبة جديدة', 'en': 'New banquet'},
  'banq_title_label': {'ar': 'عنوان المأدبة', 'en': 'Banquet title'},
  'banq_date': {'ar': 'التاريخ', 'en': 'Date'},
  'banq_time': {'ar': 'الوقت', 'en': 'Time'},
  'banq_place': {'ar': 'المكان', 'en': 'Place'},
  'banq_host': {'ar': 'المضيف', 'en': 'Host'},
  'banq_guests': {'ar': 'الضيوف والدعوات', 'en': 'Guests & invitations'},
  'banq_add_guest': {'ar': 'إضافة ضيف', 'en': 'Add guest'},
  'banq_invited': {'ar': 'مدعو', 'en': 'Invited'},
  'banq_seat': {'ar': 'مقعد طاولة الشرف', 'en': 'Head-table seat'},
  'banq_no_seat': {'ar': 'بلا مقعد محدد', 'en': 'No assigned seat'},
  'banq_no_guests': {
    'ar': 'لا يوجد ضيوف بعد — أضف المدعوين ومقاعد طاولة الشرف.',
    'en': 'No guests yet — add the invitees and head-table seats.'
  },
  'banq_program': {'ar': 'تسلسل الفقرات', 'en': 'Program sequence'},
  'banq_add_item': {'ar': 'إضافة فقرة', 'en': 'Add item'},
  'banq_item_title': {'ar': 'عنوان الفقرة', 'en': 'Item title'},
  'banq_no_items': {
    'ar': 'لا توجد فقرات بعد — أضف الاستقبال والكلمات والأنخاب والعشاء.',
    'en': 'No items yet — add reception, speeches, toasts, and dinner.'
  },
  'banq_delete_title': {'ar': 'حذف المأدبة', 'en': 'Delete banquet'},
  'banq_delete_body': {
    'ar': 'سيتم حذف مأدبة «{name}» وضيوفها وفقراتها نهائيًا.',
    'en': 'Banquet “{name}”, its guests, and its program will be permanently deleted.'
  },
  'banq_delete_fail': {
    'ar': 'تعذر حذف المأدبة، حاول مجددًا',
    'en': 'Could not delete the banquet, please try again'
  },
  'banq_save_fail': {
    'ar': 'تعذر حفظ المأدبة، حاول مجددًا',
    'en': 'Could not save the banquet, please try again'
  },
  'banq_saved': {'ar': 'تم حفظ المأدبة', 'en': 'Banquet saved'},
  'banq_need_title': {
    'ar': 'أدخل عنوانًا للمأدبة أولًا',
    'en': 'Enter a banquet title first'
  },
  'banq_guest_need_name': {
    'ar': 'أدخل اسم الضيف',
    'en': 'Enter the guest name'
  },
  // Precedence sources (V2_PLAN §1.2/1): each rank linked to its source
  // in the knowledge base where it actually appears; otherwise honestly
  // marked as undocumented. Verified against kb_topics (2026-11-25):
  // head_state → P2C1-M2-03 pp. 65–68; head_gov & crown → P2C1-M2-09
  // pp. 89–91; ambassador → P2C1-M2-04 pp. 69–71 + VCDR Arts. 13 & 16;
  // charge → VCDR Art. 14 (article 8, verified source).
  'prec_source': {'ar': 'المصدر:', 'en': 'Source:'},
  'prec_no_source': {
    'ar': 'بلا مصدر موثق — هذه الفئة غير موثقة في قاعدة المعرفة الحالية',
    'en': 'No documented source — this category is not documented in the current knowledge base'
  },
  'prec_delete_title': {'ar': 'حذف الشخص', 'en': 'Remove person'},
  'prec_delete_body': {
    'ar': 'سيتم حذف «{name}» من القائمة.',
    'en': '“{name}” will be removed from the list.'
  },
  // Seating overflow: never hide extra guests silently (V2_PLAN §1.2/2)
  'seat_overflow_title': {'ar': 'ضيوف زائدون عن المقاعد', 'en': 'More guests than seats'},
  'seat_overflow_body': {
    'ar': 'عدد الضيوف ({n}) يتجاوز المقاعد ({seats}). الضيوف التالية أسماؤهم لن يظهر لهم مقعد:\n{names}\nاختر: زيادة المقاعد لاستيعاب الجميع، أو إلغاء الحفظ.',
    'en': 'Guests ({n}) exceed the seats ({seats}). These guests would have no seat:\n{names}\nChoose: increase the seats to fit everyone, or cancel saving.'
  },
  'seat_overflow_grow': {
    'ar': 'زيادة المقاعد إلى {n} وحفظ',
    'en': 'Increase seats to {n} and save'
  },
  'seat_overflow_warn': {
    'ar': 'تنبيه: {n} ضيوف زائدين عن المقاعد — لن يظهر لهم مقعد على المائدة',
    'en': 'Warning: {n} guests over the seat count — they will have no seat at the table'
  },
  // Document generator — recipient filter (ready templates only, §5)
  'docs_recipient': {'ar': 'الجهة المستقبلة', 'en': 'Recipient'},
  'docs_recipient_all': {'ar': 'كل الجهات', 'en': 'All recipients'},
  'docs_recipient_embassy': {
    'ar': 'سفارة / بعثة دبلوماسية',
    'en': 'Embassy / diplomatic mission'
  },
  'docs_recipient_gov': {
    'ar': 'وزارة / جهة حكومية',
    'en': 'Ministry / government body'
  },
  'docs_recipient_guest': {'ar': 'ضيف رسمي', 'en': 'Official guest'},
  'docs_no_template_for_recipient': {
    'ar': 'لا يوجد قالب جاهز لهذه الجهة. الأنواع الأخرى في المواصفة (شكر، تهنئة، اعتذار، تعزية، مخاطبات حكومية) بلا قالب جاهز في قاعدة البيانات الحالية وتتطلب المساعد التوليدي — غير متاح بعد — ولا تُولَّد هنا.',
    'en': 'No ready template for this recipient. The other types in the specification (thanks, congratulations, apology, condolence, government correspondence) have no ready template in the current database and require the generative assistant — not available yet — and are not generated here.'
  },
  // Program time validation
  'program_time_invalid': {
    'ar': 'الوقت غير صحيح: الساعة 00–23 والدقيقة 00–59 (مثال: 10:30)',
    'en': 'Invalid time: hour 00–23 and minute 00–59 (e.g. 10:30)'
  },
  // Saved chats
  'chat_new': {'ar': 'محادثة جديدة', 'en': 'New conversation'},
  'chat_history': {'ar': 'سجل المحادثات', 'en': 'Conversation history'},
  'chat_empty': {
    'ar': 'لا محادثات محفوظة بعد.\nاسأل المساعد وستُحفظ محادثتك هنا على جهازك.',
    'en': 'No saved conversations yet.\nAsk the assistant and your conversation will be saved here on your device.'
  },
  'chat_delete_title': {'ar': 'حذف المحادثة', 'en': 'Delete conversation'},
  'chat_delete_body': {
    'ar': 'سيتم حذف محادثة «{name}» ورسائلها نهائيًا.',
    'en': 'Conversation “{name}” and its messages will be permanently deleted.'
  },
  'chat_delete_fail': {
    'ar': 'تعذر حذف المحادثة، حاول مجددًا',
    'en': 'Could not delete the conversation, please try again'
  },
  'chat_messages_count': {
    'ar': '{n} رسائل',
    'en': '{n} messages'
  },
  'chat_local_note': {
    'ar': 'محفوظة على جهازك فقط — لا تُرسل أي بيانات خارج الجهاز.',
    'en': 'Saved on your device only — no data leaves the device.'
  },
  'archives_chats_sub': {
    'ar': 'محادثاتك مع المساعد محفوظة على جهازك',
    'en': 'Your conversations with the assistant, saved on your device'
  },
  'version': {'ar': 'الإصدار', 'en': 'Version'},
};

String tr(AppState s, String key) {
  final m = _strings[key];
  if (m == null) return key;
  return m[s.language] ?? m['ar']!;
}

/// Translation lookup from a build context (reads the current language from
/// the nearest AppState). Use inside widgets that do not hold AppState.
String trc(BuildContext context, String key) {
  final lang = Provider.of<AppState>(context, listen: false).language;
  final m = _strings[key];
  if (m == null) return key;
  return m[lang] ?? m['ar']!;
}

/// Current app version (keep in sync with pubspec.yaml).
const appVersion = '1.0.1';

/// English display labels for precedence rank keys (Arabic labels live in
/// db.dart rankLabel). Content values are never translated — only the UI.
const rankLabelsEn = {
  'head_state': 'Head of State / King / Ruling Prince',
  'head_gov': 'Head of Government',
  'crown': 'Crown Prince / Vice President',
  'foreign_minister': 'Foreign Minister',
  'ambassador': 'Ambassador',
  'minister': 'Minister',
  'charge': "Chargé d'affaires",
  'deputy_minister': 'Undersecretary / Deputy Minister',
  'director_general': 'Director General',
  'senior_official': 'Senior Official',
};

/// Rank display label in the current UI language.
String rankLabelTr(BuildContext context, String key) {
  if (Provider.of<AppState>(context, listen: false).language == 'en') {
    return rankLabelsEn[key] ?? key;
  }
  return rankLabel(key);
}
