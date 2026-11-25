import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'ai/llama_qwen_provider.dart';
import 'ai/llm_provider.dart';
import 'ai/provider_factory.dart';
import 'ai/retrieval_core.dart' show ChunkOrigin, RetrievedChunk;
import 'ai/retrieval_service.dart';
import 'app_state.dart';
import 'db.dart';
import 'encyclopedia.dart';
import 'saved_chats.dart';
import 'tools.dart';
import 'widgets.dart';

/// PROTOCOL AI — assistant over the local knowledge base, provider-swappable.
/// With the local model downloaded (P6: Qwen GGUF via fllama_cpp) it
/// generates answers strictly grounded in the retrieved chunks, citing
/// book page numbers; without it — or when the model fails to load —
/// it falls back automatically to retrieval-only mode and says so
/// honestly in the banner. When no reliable information exists, it
/// shows the fixed refusal sentence verbatim. Works fully offline
/// once the model is downloaded.
/// المساعد: توليد محلي مقيّد بالمقاطع عند جاهزية النموذج، وإلا وضع
/// استرجاعي مع وسم صادق — لا شبكة ولا مفاتيح هنا.
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _Msg {
  final bool user;
  final String text;
  final RetrievedChunk? top;
  final List<RetrievedChunk> related;
  final bool noInfo;
  const _Msg(
      {required this.user,
      required this.text,
      this.top,
      this.related = const [],
      this.noInfo = false});
}

const _chips = [
  ('كيف أرتب جلوس وفد يضم خمس دول؟', 'ترتيب جلوس وفد دول'),
  ('ما ترتيب الأسبقية في حفل استقبال رسمي؟', 'ترتيب الأسبقية حفل استقبال'),
  ('كيف أعد برنامج زيارة لوفد دبلوماسي؟', 'برنامج زيارة وفد دبلوماسي'),
  ('كيف تتم مراسم توقيع اتفاقية دولية؟', 'مراسم توقيع اتفاقية'),
  ('ما الفرق بين الزيارة الرسمية وزيارة العمل؟', 'الفرق زيارة رسمية زيارة عمل'),
  ('كيف أرتب أعلام الدول المشاركة؟', 'ترتيب أعلام الدول'),
  ('كيف أكتب دعوة رسمية لسفير؟', 'دعوة رسمية سفير'),
];

class _AssistantPageState extends State<AssistantPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final List<_Msg> _msgs;
  bool _busy = false;
  // المزود الحالي: النموذج المحلي عند جاهزيته، وإلا الاسترجاعي.
  LlmProvider? _provider;
  // وسم صادق عن وضع التشغيل (يُحدَّث عند حلّ المزود وعند أي سقوط).
  String _modeTag =
      'وضع استرجاعي: يبحث في قاعدة المعرفة فقط — بلا توليد';
  // فشل تحميل سابق للنموذج يجبر العودة إلى الاسترجاعي.
  bool _modelFailed = false;
  // أسلوب الإجابة وطولها (للتوليد المحلي؛ الاسترجاعي يقتبس حرفياً).
  AnswerStyle _style = AnswerStyle.diplomatic;
  AnswerLength _length = AnswerLength.medium;
  // المحادثة الحالية في قاعدة البيانات المحلية؛ null تعني أن أول
  // سؤال قادم سيفتح محادثة جديدة (عنوان تلقائي من أول سؤال).
  int? _conversationId;

  @override
  void initState() {
    super.initState();
    _msgs = [
      _Msg(user: false, text: trc(context, 'assistant_welcome')),
    ];
    _initProvider();
  }

  /// يحلّ المزود عند الإقلاع: النموذج المحلي عند جاهزيته، وإلا
  /// الاسترجاعي مع وسمه الصادق. لا يكسر المحادثة أبداً عند الفشل.
  Future<void> _initProvider() async {
    final resolved = await resolveAssistantProvider(
      lastLoadOk: !_modelFailed,
    );
    if (!mounted) return;
    setState(() {
      _provider = resolved.provider;
      _modeTag = assistantModeTag(resolved.decision);
    });
  }

  /// عنوان تلقائي من أول سؤال (40 حرفاً كحد أقصى).
  static String _autoTitle(String q) {
    final t = q.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= 40 ? t : '${t.substring(0, 40).trim()}…';
  }

  /// حفظ تلقائي للتبادل (سؤال + إجابة + استشهادات) في المحادثات
  /// المحفوظة على الجهاز فقط. الفشل هنا لا يكسر المحادثة أبداً.
  Future<void> _saveExchange(
      String question, String answer, String citations) async {
    try {
      final now = DateTime.now().toIso8601String();
      _conversationId ??= await Repo.i.insertChatConversation({
        'title': _autoTitle(question),
        'created_at': now,
        'updated_at': now,
      });
      await Repo.i.insertChatMessage({
        'conversation_id': _conversationId!,
        'role': 'user',
        'text': question,
        'citations': '',
        'created_at': now,
      });
      await Repo.i.insertChatMessage({
        'conversation_id': _conversationId!,
        'role': 'assistant',
        'text': answer,
        'citations': citations,
        'created_at': now,
      });
      await Repo.i.touchChatConversation(_conversationId!);
    } catch (_) {
      // Saving must never break the conversation.
    }
  }

  void _newConversation() {
    setState(() {
      _conversationId = null;
      _msgs
        ..clear()
        ..add(_Msg(user: false, text: trc(context, 'assistant_welcome')));
    });
  }

  Future<void> _ask(String query) async {
    final q = query.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _msgs.add(_Msg(user: true, text: q));
      _busy = true;
    });
    _controller.clear();
    _scrollToEnd();
    try {
      if (_provider == null || _provider is RetrievalOnlyProvider) {
        await _askRetrieval(q);
      } else {
        await _askGenerative(q);
      }
    } catch (_) {
      if (!mounted) return;
      final err = trc(context, 'assistant_search_error');
      setState(() {
        _msgs.add(_Msg(
          user: false,
          text: err,
          noInfo: true,
        ));
      });
      await _saveExchange(q, err, '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _scrollToEnd();
  }

  /// المسار الاسترجاعي (بلا توليد): يقتبس المقاطع حرفياً مع
  /// الاستشهادات — وهو أيضاً مسار السقوط عند فشل النموذج المحلي.
  Future<void> _askRetrieval(String q) async {
    final result = await RetrievalService().retrieve(q, limit: 6);
    if (!mounted) return;
    if (result.refused || result.top == null) {
      final refusal = trc(context, 'assistant_no_info');
      setState(() {
        _msgs.add(_Msg(
          user: false,
          // جملة الرفض الثابتة حرفياً (assistant_no_info).
          text: refusal,
          noInfo: true,
        ));
      });
      await _saveExchange(q, refusal, '');
    } else {
      final intro = trc(context, 'assistant_answer_intro');
      final top = result.top!;
      setState(() {
        _msgs.add(_Msg(
          user: false,
          text: intro,
          top: top,
          related: result.related,
        ));
      });
      await _saveExchange(
          q, '$intro\n${top.title}\n${top.excerpt}', top.citationLine);
    }
  }

  /// المسار التوليدي المحلي: النموذج يجيب مقيداً بالمقاطع المسترجعة
  /// مع الاستشهاد بصفحات الكتاب. عند رفض الاسترجاع يعرض المزود
  /// جملة الرفض حرفياً دون توليد. عند أي خطأ في النموذج يسقط
  /// المساعد إلى الوضع الاسترجاعي ويعيد المحاولة به مرة واحدة.
  Future<void> _askGenerative(String q) async {
    final provider = _provider!;
    // ذاكرة السياق: تبادلات سابقة فقط — بلا رسالة الترحيب وبلا
    // السؤال الحالي (يُمرَّر كـuserPrompt). آخر 3 تبادلات (6 رسائل).
    final history = <ChatMessage>[];
    final prior = _msgs.length > 2
        ? _msgs.sublist(1, _msgs.length - 1)
        : const <_Msg>[];
    final tail =
        prior.length > 6 ? prior.sublist(prior.length - 6) : prior;
    for (final m in tail) {
      history.add(
        ChatMessage(role: m.user ? 'user' : 'assistant', text: m.text),
      );
    }
    try {
      final result = await provider.generate(GenerationRequest(
        userPrompt: q,
        style: _style,
        length: _length,
        maxTokens: maxTokensForLength(_length),
        history: history,
      ));
      if (!mounted) return;
      if (result.refused) {
        final refusal = trc(context, 'assistant_no_info');
        setState(() {
          _msgs.add(_Msg(user: false, text: refusal, noInfo: true));
        });
        await _saveExchange(q, refusal, '');
        return;
      }
      setState(() {
        _msgs.add(_Msg(user: false, text: result.text));
      });
      await _saveExchange(
        q,
        result.text,
        result.citations.map((c) => c.citationLine).join('\n'),
      );
    } on LlamaModelException {
      // سقوط صادق إلى الاسترجاعي: لا إجابة وهمية ولا تعطّل.
      _modelFailed = true;
      await _initProvider();
      if (!mounted) return;
      await _askRetrieval(q);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(trc(context, 'assistant_full')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: trc(context, 'chat_new'),
            onPressed: _newConversation,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: trc(context, 'chat_history'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SavedConversationsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(trc(context, 'assistant_how_title')),
                content: Text(trc(context, 'assistant_how_body')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(trc(context, 'assistant_understood'))),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // وسم صادق عن وضع المساعد: توليد محلي مقيّد بالمقاطع عند
          // جاهزية النموذج، وإلا وضع استرجاعي — لا يُقدَّم أحدهما
          // على أنه الآخر أبداً.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              _modeTag,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.mutedColor),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (ctx, i) => _bubble(_msgs[i]),
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(trc(context, 'assistant_searching'),
                      style: TextStyle(color: context.mutedColor)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                // اختيار أسلوب الإجابة وطولها (للتوليد المحلي؛
                // الاسترجاعي يقتبس حرفياً فلا يتأثر بهما).
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<AnswerStyle>(
                        value: _style,
                        isExpanded: true,
                        items: AnswerStyle.values
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    context.read<AppState>().language == 'en'
                                        ? answerStyleLabelsEn[s]!
                                        : answerStyleLabelsAr[s]!,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            v != null ? setState(() => _style = v) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<AnswerLength>(
                      value: _length,
                      items: AnswerLength.values
                          .map((l) => DropdownMenuItem(
                                value: l,
                                child: Text(
                                  context.read<AppState>().language == 'en'
                                      ? answerLengthLabelsEn[l]!
                                      : answerLengthLabelsAr[l]!,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          v != null ? setState(() => _length = v) : null,
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _chips
                        .map((c) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: ActionChip(
                                label: Text(c.$1),
                                onPressed: () => _ask(c.$2),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.description_outlined,
                          color: AppColors.gold),
                      tooltip: trc(context, 'assistant_draft'),
                      onPressed: () => _showDraftSheet(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fact_check_outlined,
                          color: AppColors.gold),
                      tooltip: trc(context, 'assistant_check_plan'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CheckerPickerPage()),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: trc(context, 'assistant_write_question'),
                          border: InputBorder.none,
                        ),
                        onSubmitted: _ask,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.gold),
                      onPressed: () => _ask(_controller.text),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 14, color: context.mutedColor),
                    const SizedBox(width: 4),
                    Text(trc(context, 'assistant_offline_note'),
                        style:
                            TextStyle(fontSize: 11, color: context.mutedColor)),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDraftSheet() {
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
              Text(trc(context, 'assistant_draft'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(trc(context, 'assistant_draft_sub'),
                  style: TextStyle(color: context.mutedColor)),
              const SizedBox(height: 12),
              ...[
                ('invitation', trc(context, 'draft_invitation')),
                ('visit_program', trc(context, 'draft_visit_program')),
                ('meeting_agenda', trc(context, 'draft_meeting_agenda')),
                ('event_checklist', trc(context, 'draft_event_checklist')),
              ].map((t) => ListTile(
                    leading:
                        const Icon(Icons.description, color: AppColors.navy),
                    title: Text(t.$2),
                    trailing: const Icon(Icons.arrow_back_ios, size: 14),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                DocGeneratorPage(templateKey: t.$1)),
                      );
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final align = m.user ? Alignment.centerLeft : Alignment.centerRight;
    final color = m.user ? AppColors.navy : Theme.of(context).cardColor;
    final textColor = m.user ? Colors.white : context.bodyColor;
    final linkColor = context.isDark ? AppColors.gold : AppColors.navy;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: m.user ? null : Border.all(color: context.cardBorderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text, style: TextStyle(color: textColor, fontSize: 14.5)),
            if (m.top != null) ...[
              const SizedBox(height: 8),
              Text(m.top!.title,
                  style: TextStyle(
                      fontFamily: 'Amiri',
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const SizedBox(height: 4),
              Text(m.top!.excerpt,
                  style: TextStyle(color: textColor, fontSize: 14)),
              const SizedBox(height: 10),
              // الاستشهاد: اسم الموضوع ورقم صفحة الكتاب.
              Text(m.top!.citationLine,
                  style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              if (m.top!.textStatus.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('حالة النص: ${m.top!.textStatus}',
                    style: TextStyle(color: context.mutedColor, fontSize: 11)),
              ],
              if (m.related.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(trc(context, 'assistant_related'),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: textColor)),
                ...m.related.map((c) {
                  final label = c.hasBookPages
                      ? '${c.title} — ${c.bookPagesLabel}'
                      : c.title;
                  final row = Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.article_outlined,
                            size: 15, color: linkColor),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(label,
                                style:
                                    TextStyle(color: linkColor, fontSize: 13))),
                      ],
                    ),
                  );
                  // مواضيع الكتاب بلا صفحة قارئ بعد؛ المقالات فقط
                  // تُفتح في قارئ المقالات.
                  if (c.origin == ChunkOrigin.article && c.articleId != null) {
                    return InkWell(
                      onTap: () async {
                        final a = await Repo.i.articleById(c.articleId!);
                        if (a == null || !mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ArticleReaderPage(article: a)),
                        );
                      },
                      child: row,
                    );
                  }
                  return row;
                }),
              ],
            ],
            if (m.noInfo) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_book, size: 16),
                label: Text(trc(context, 'assistant_browse_guide')),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProtocolGuidePage()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Article reader (also used from search results and related links).
class ArticleReaderPage extends StatefulWidget {
  final Article article;
  const ArticleReaderPage({super.key, required this.article});
  @override
  State<ArticleReaderPage> createState() => _ArticleReaderPageState();
}

class _ArticleReaderPageState extends State<ArticleReaderPage> {
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    Repo.i.isFav('article', widget.article.id).then((v) {
      if (mounted) setState(() => _fav = v);
    });
    // Remember the last article opened, for "Continue reading" (Home and
    // Archives). Fire-and-forget: reading must never wait on this write.
    Repo.i.setSetting('last_read_article_id', widget.article.id.toString());
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return Scaffold(
      appBar: AppBar(
        title: Text(a.section, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(_fav ? Icons.star : Icons.star_border,
                color: AppColors.gold),
            onPressed: () async {
              await Repo.i.toggleFav('article', a.id);
              if (mounted) setState(() => _fav = !_fav);
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(
                '${a.title}\n\n${a.body}\n\nالمصدر: ${a.sourceName} — ${a.sourceOrg}'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.title,
                style: const TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(a.body, style: const TextStyle(fontSize: 16, height: 1.9)),
            const SizedBox(height: 16),
            SourceLine(
              sourceName: a.sourceName,
              sourceOrg: a.sourceOrg,
              sourceUrl: a.sourceUrl,
              reviewed: a.reviewed,
              ruleType: a.ruleType,
            ),
          ],
        ),
      ),
    );
  }
}
