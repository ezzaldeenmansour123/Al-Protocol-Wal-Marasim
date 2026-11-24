import 'package:material_ui/material_ui.dart';
import 'app_state.dart';
import 'db.dart';
import 'widgets.dart';

/// المحادثات المحفوظة (CHARTER_V2 §4.6): قائمة المحادثات وفتحها
/// وحذفها. كل البيانات محلية على الجهاز فقط — لا تُرسل خارجاً.
/// الحفظ نفسه تلقائي من المساعد (lib/assistant.dart).

class SavedConversationsPage extends StatefulWidget {
  const SavedConversationsPage({super.key});
  @override
  State<SavedConversationsPage> createState() =>
      _SavedConversationsPageState();
}

class _SavedConversationsPageState extends State<SavedConversationsPage> {
  List<Map<String, Object?>> _convs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final convs = await Repo.i.allChatConversations();
    if (mounted) setState(() => _convs = convs);
  }

  Future<void> _delete(Map<String, Object?> c) async {
    final title = (c['title'] ?? '') as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trc(context, 'chat_delete_title')),
        content: Text(trc(context, 'chat_delete_body')
            .replaceFirst('{name}', title)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(trc(context, 'cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(trc(context, 'delete'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Repo.i.deleteChatConversation(c['id'] as int);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(trc(context, 'chat_delete_fail'))));
      }
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(trc(context, 'archives_chats'))),
      body: _convs.isEmpty
          ? EmptyState(
              icon: Icons.chat_bubble_outline,
              text: trc(context, 'chat_empty'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _convs.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(trc(context, 'chat_local_note'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: context.mutedColor)),
                  );
                }
                final c = _convs[i - 1];
                final title = (c['title'] ?? '') as String;
                final count = (c['msg_count'] as int?) ?? 0;
                final updated = ((c['updated_at'] ?? '') as String)
                    .split('T')
                    .first;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.chat_bubble_outline,
                        color: AppColors.navy),
                    title: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${trc(context, 'chat_messages_count').replaceFirst('{n}', '$count')} • $updated'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      onPressed: () => _delete(c),
                    ),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ChatConversationPage(
                                  conversationId: c['id'] as int,
                                  title: title)));
                      _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// عرض محادثة محفوظة كاملة (قراءة فقط): أسئلة المستخدم وإجابات
/// المساعد مع الاستشهادات المحفوظة معها.
class ChatConversationPage extends StatefulWidget {
  final int conversationId;
  final String title;
  const ChatConversationPage(
      {super.key, required this.conversationId, required this.title});
  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  List<Map<String, Object?>> _msgs = [];

  @override
  void initState() {
    super.initState();
    Repo.i.chatMessages(widget.conversationId).then((m) {
      if (mounted) setState(() => _msgs = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _msgs.isEmpty
          ? EmptyState(
              icon: Icons.chat_bubble_outline,
              text: trc(context, 'chat_empty'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (ctx, i) {
                final m = _msgs[i];
                final isUser = (m['role'] ?? '') == 'user';
                final text = (m['text'] ?? '') as String;
                final citations = (m['citations'] ?? '') as String;
                return Align(
                  alignment:
                      isUser ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width * 0.85),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.navy
                          : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: isUser
                          ? null
                          : Border.all(color: context.cardBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text,
                            style: TextStyle(
                                color: isUser
                                    ? Colors.white
                                    : context.bodyColor,
                                fontSize: 14.5,
                                height: 1.7)),
                        if (citations.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(citations,
                              style: TextStyle(
                                  color: isUser
                                      ? Colors.white70
                                      : context.mutedColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
