import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../../models/chat_message.dart';
import '../../../models/chat_pinned_message.dart';
import '../../../models/chat_thread.dart';
import '../../../services/chat_service.dart';
import '../../../services/supabase_service.dart';

class InboxScreen extends StatefulWidget {
  final ValueChanged<bool>? onConversationViewChanged;

  const InboxScreen({super.key, this.onConversationViewChanged});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  int _selectedFilter = 0;
  int _selectedConversation = 0;
  bool _showMobileChat = false;
  bool _isLoading = true;
  String _searchQuery = '';
  Set<int> _pinnedChats = {};

  final ChatService _chatService = ChatService();
  dynamic _inboxSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  int? _activeChatId;
  final Map<int, List<ChatMessage>> _rawMessagesByChat = {};
  final Map<int, List<_Message>> _messagesByChat = {};
  final Map<int, List<ChatPinnedMessage>> _chatPins = {};
  final TextEditingController _composerController = TextEditingController();
  _Message? _replyingTo;
  bool _isSending = false;

  int? get _currentUserId => _chatService.currentUserId;

  @override
  void initState() {
    super.initState();
    _loadPinned();
    if (SupabaseService.isConfigured) {
      _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
        (_) => _handleUserChanged(),
      );
    }
    _loadInbox();
    try {
      _inboxSubscription = _chatService.subscribeInboxChanges(
        onChange: _loadInbox,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _messagesSubscription?.cancel();
    if (_inboxSubscription != null) {
      _chatService.unsubscribeInboxChanges(_inboxSubscription);
    }
    _composerController.dispose();
    super.dispose();
  }

  void _handleUserChanged() {
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _activeChatId = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedConversation = 0;
      _showMobileChat = false;
      _isLoading = true;
      _replyingTo = null;
      _rawMessagesByChat.clear();
      _messagesByChat.clear();
      _chatPins.clear();
    });
    _composerController.clear();
    _loadInbox();
  }

  Future<void> _loadInbox() async {
    try {
      final threads = await _chatService.loadInbox();
      final currentUserId = _currentUserId;
      final mapped = threads.map((t) {
        return _Conversation(
          id: t.id,
          chatThread: t,
          name: currentUserId == null
              ? (t.user2Name ?? t.user1Name ?? 'User')
              : t.otherUserName(currentUserId),
          status: 'Active',
          badge: null,
          timeAgo: _formatTime(t.updatedAt),
          preview: t.lastMessage ?? 'No messages yet',
          avatarColors: const [Color(0xFFE7DFFF), Color(0xFFC18EFF)],
          item: null,
          messages: _messagesByChat[t.id] ?? const [],
        );
      }).toList();

      if (mounted) {
        setState(() {
          _allConversations.clear();
          _allConversations.addAll(mapped);
          if (_selectedConversation >= _allConversations.length) {
            _selectedConversation = 0;
          }
          _isLoading = false;
        });
      }
      _subscribeToSelectedConversationMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint('Error loading inbox: $e');
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedRaw = prefs.getStringList('pinned_chats') ?? [];
    final pinned = pinnedRaw.map(int.tryParse).whereType<int>().toSet();
    setState(() {
      _pinnedChats = pinned;
    });
  }

  Future<void> _togglePin(int id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_pinnedChats.contains(id)) {
        _pinnedChats.remove(id);
      } else {
        _pinnedChats.add(id);
      }
    });
    await prefs.setStringList(
      'pinned_chats',
      _pinnedChats.map((id) => id.toString()).toList(),
    );
  }

  static const _filters = ['All', 'Selling', 'Buying'];

  final List<_Conversation> _allConversations = [];

  List<_Conversation> get _conversations {
    List<_Conversation> filtered = _allConversations.where((conv) {
      final matchesSearch =
          conv.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          conv.preview.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      final isSelling = _isSellingConversation(conv);
      if (_selectedFilter == 1 && !isSelling) return false; // Selling
      if (_selectedFilter == 2 && isSelling) return false; // Buying
      return true;
    }).toList();

    // Sort pinned to top
    filtered.sort((a, b) {
      final aPinned = _pinnedChats.contains(a.id);
      final bPinned = _pinnedChats.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0; // fallback to original order
    });

    return filtered;
  }

  bool _isSellingConversation(_Conversation conv) {
    final chat = conv.chatThread;
    if (chat == null) {
      return false;
    }

    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return false;
    }

    // Prefer explicit item owner when available. If join data is missing,
    // fallback to user1 as owner to match current chat creation flow.
    final ownerId = chat.itemOwnerId ?? chat.user1Id;
    return ownerId == currentUserId;
  }

  void _onFilterSelected(int index) {
    setState(() {
      _selectedFilter = index;
      _selectedConversation = 0;
      if (_conversations.isEmpty) {
        _showMobileChat = false;
      }
    });
    _subscribeToSelectedConversationMessages();
  }

  void _onConversationSelected(int index, {bool openMobile = false}) {
    setState(() {
      _selectedConversation = index;
      _replyingTo = null;
    });
    if (openMobile) {
      _setMobileConversationView(true);
    }
    _subscribeToSelectedConversationMessages();
  }

  void _subscribeToSelectedConversationMessages() {
    final selected = _conversations.isNotEmpty
        ? _conversations[_selectedConversation < _conversations.length
              ? _selectedConversation
              : 0]
        : null;

    if (selected == null) {
      _messagesSubscription?.cancel();
      _messagesSubscription = null;
      _activeChatId = null;
      return;
    }

    _loadPinnedMessagesForChat(selected.id);

    if (_activeChatId == selected.id && _messagesSubscription != null) {
      return;
    }

    _messagesSubscription?.cancel();
    _activeChatId = selected.id;
    _messagesSubscription = _chatService
        .watchMessages(selected.id)
        .listen(
          (messages) {
            if (!mounted) {
              return;
            }
            final messageById = {for (final m in messages) m.id: m};
            final uiMessages = messages
                .map((m) => _toUiMessage(message: m, messageById: messageById))
                .toList();

            final hasUnreadIncoming = messages.any(
              (m) => m.senderId != _currentUserId && m.readAt == null,
            );
            if (hasUnreadIncoming) {
              _chatService.markChatAsRead(selected.id).catchError((_) {});
            }

            setState(() {
              _rawMessagesByChat[selected.id] = messages;
              _messagesByChat[selected.id] = uiMessages;
              final index = _allConversations.indexWhere(
                (c) => c.id == selected.id,
              );
              if (index != -1) {
                _allConversations[index] = _allConversations[index].copyWith(
                  messages: uiMessages,
                );
              }
            });
          },
          onError: (error) {
            debugPrint('Error watching messages: $error');
          },
        );
  }

  Future<void> _loadPinnedMessagesForChat(int chatId) async {
    try {
      final pins = await _chatService.listPinnedMessages(chatId);
      if (!mounted) {
        return;
      }
      setState(() {
        _chatPins[chatId] = pins;
      });
    } catch (e) {
      debugPrint('Error loading pinned messages: $e');
    }
  }

  _Message _toUiMessage({
    required ChatMessage message,
    required Map<int, ChatMessage> messageById,
  }) {
    final parsed = _parseReplyMetadata(message.content);
    final displayText = parsed.messageText;
    final replied = parsed.repliedMessageId == null
        ? null
        : messageById[parsed.repliedMessageId!];

    final local = message.createdAt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    final replyText = replied == null
        ? null
        : _parseReplyMetadata(replied.content).messageText;

    return _Message(
      id: message.id,
      text: displayText,
      time: '$hour:$minute $suffix',
      isMine: message.senderId == _currentUserId,
      senderId: message.senderId,
      createdAt: message.createdAt,
      readAt: message.readAt,
      editedAt: message.editedAt,
      deletedAt: message.deletedAt,
      replyToMessageId: parsed.repliedMessageId,
      replyToText: replyText,
    );
  }

  ({int? repliedMessageId, String messageText}) _parseReplyMetadata(
    String content,
  ) {
    const prefix = '[[reply:';
    if (!content.startsWith(prefix)) {
      return (repliedMessageId: null, messageText: content);
    }

    final closeIndex = content.indexOf(']]');
    if (closeIndex == -1) {
      return (repliedMessageId: null, messageText: content);
    }

    final repliedMessageIdRaw = content
        .substring(prefix.length, closeIndex)
        .trim();
    final body = content.substring(closeIndex + 2).trimLeft();
    if (repliedMessageIdRaw.isEmpty) {
      return (repliedMessageId: null, messageText: body);
    }
    final repliedMessageId = int.tryParse(repliedMessageIdRaw);
    if (repliedMessageId == null) {
      return (repliedMessageId: null, messageText: body);
    }
    return (repliedMessageId: repliedMessageId, messageText: body);
  }

  bool _canModifyMessage(_Message message) {
    if (!message.isMine || message.deletedAt != null || message.isLocal) {
      return false;
    }
    return DateTime.now().difference(message.createdAt) <=
        const Duration(minutes: 3);
  }

  Future<void> _showMessageActions({
    required _Conversation conversation,
    required _Message message,
  }) async {
    final canModify = _canModifyMessage(message);
    final canPin = !message.isLocal;
    final isPinned = (_chatPins[conversation.id] ?? const <ChatPinnedMessage>[])
        .any((pin) => pin.messageId == message.id);

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyingTo = message;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.text));
                },
              ),
              if (canModify)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _editMessage(message);
                  },
                ),
              if (canModify)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(message);
                  },
                ),
              if (canPin)
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(isPinned ? 'Unpin' : 'Pin'),
                  onTap: () {
                    Navigator.pop(context);
                    if (isPinned) {
                      _unpinMessage(conversation, message);
                    } else {
                      _pinMessage(conversation, message);
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: const Text('Translate'),
                subtitle: const Text('Coming soon'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('Translate will be implemented later.'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editMessage(_Message message) async {
    if (message.isLocal) {
      return;
    }

    final controller = TextEditingController(text: message.text);
    final updatedText = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updatedText == null ||
        updatedText.isEmpty ||
        updatedText == message.text) {
      return;
    }

    try {
      await _chatService.editMessage(
        messageId: message.id,
        content: updatedText,
      );
    } catch (e) {
      debugPrint('Error editing message: $e');
    }
  }

  Future<void> _deleteMessage(_Message message) async {
    if (message.isLocal) {
      return;
    }

    try {
      await _chatService.deleteMessage(message.id);
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  Future<void> _pinMessage(_Conversation conversation, _Message message) async {
    if (message.isLocal) {
      return;
    }

    try {
      await _chatService.pinMessage(
        chatId: conversation.id,
        messageId: message.id,
      );
      await _loadPinnedMessagesForChat(conversation.id);
      await _loadInbox();
    } catch (e) {
      debugPrint('Error pinning message: $e');
    }
  }

  Future<void> _unpinMessage(
    _Conversation conversation,
    _Message message,
  ) async {
    if (message.isLocal) {
      return;
    }

    try {
      await _chatService.clearPinnedMessage(
        chatId: conversation.id,
        messageId: message.id,
      );
      await _loadPinnedMessagesForChat(conversation.id);
      await _loadInbox();
    } catch (e) {
      debugPrint('Error clearing pin: $e');
    }
  }

  Future<void> _sendCurrentMessage(_Conversation conversation) async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    final replyingTo = _replyingTo;
    final payload = replyingTo == null
        ? text
        : '[[reply:${replyingTo.id}]]\n$text';

    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final suffix = now.hour >= 12 ? 'PM' : 'AM';
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return;
    }

    final optimistic = _Message(
      id: -now.microsecondsSinceEpoch,
      text: text,
      time: '$hour:$minute $suffix',
      isMine: true,
      senderId: currentUserId,
      createdAt: now,
      readAt: null,
      editedAt: null,
      deletedAt: null,
      replyToMessageId: replyingTo?.id,
      replyToText: replyingTo?.text,
    );

    _composerController.clear();
    setState(() => _isSending = true);
    try {
      setState(() {
        final existing = List<_Message>.from(
          _messagesByChat[conversation.id] ?? const [],
        );
        existing.add(optimistic);
        _messagesByChat[conversation.id] = existing;

        final index = _allConversations.indexWhere(
          (c) => c.id == conversation.id,
        );
        if (index != -1) {
          _allConversations[index] = _allConversations[index].copyWith(
            messages: existing,
            preview: text,
            timeAgo: 'Just now',
          );
        }
        _replyingTo = null;
      });

      await _chatService.sendMessage(chatId: conversation.id, content: payload);
      if (!mounted) {
        return;
      }
    } catch (e) {
      if (mounted) {
        _composerController.text = text;
        setState(() {
          _replyingTo = replyingTo;
          final existing = List<_Message>.from(
            _messagesByChat[conversation.id] ?? const [],
          );
          existing.removeWhere((m) => m.id == optimistic.id);
          _messagesByChat[conversation.id] = existing;
        });
      }
      debugPrint('Error sending message: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _setMobileConversationView(bool isOpen) {
    if (_showMobileChat == isOpen) {
      return;
    }

    setState(() => _showMobileChat = isOpen);
    widget.onConversationViewChanged?.call(isOpen);
  }

  void _syncShellChrome(bool isWide) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onConversationViewChanged?.call(!isWide && _showMobileChat);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4FF),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 950;
            final selected = _conversations.isNotEmpty
                ? _conversations[_selectedConversation < _conversations.length
                      ? _selectedConversation
                      : 0]
                : null;
            final pins = selected == null
                ? const <ChatPinnedMessage>[]
                : (_chatPins[selected.id] ?? const <ChatPinnedMessage>[]);
            final pinnedMessages = selected == null
                ? const <_Message>[]
                : pins
                      .map((pin) {
                        final idx = selected.messages.indexWhere(
                          (m) => m.id == pin.messageId,
                        );
                        return idx == -1 ? null : selected.messages[idx];
                      })
                      .whereType<_Message>()
                      .toList();
            _syncShellChrome(isWide);

            if (isWide) {
              return Row(
                children: [
                  SizedBox(
                    width: 430,
                    child: _InboxPanel(
                      conversations: _conversations,
                      filters: _filters,
                      selectedFilter: _selectedFilter,
                      selectedIndex: _selectedConversation,
                      onFilterSelected: _onFilterSelected,
                      onConversationSelected: (index) =>
                          _onConversationSelected(index),
                      searchQuery: _searchQuery,
                      onSearchChanged: (q) => setState(() => _searchQuery = q),
                      pinnedChats: _pinnedChats,
                      onPinToggled: _togglePin,
                      isLoading: _isLoading,
                    ),
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFFE7DFFF)),
                  Expanded(
                    child: selected != null
                        ? _ChatPanel(
                            conversation: selected,
                            onBack: null,
                            messageController: _composerController,
                            onSend: () => _sendCurrentMessage(selected),
                            isSending: _isSending,
                            replyingTo: _replyingTo,
                            pinnedMessages: pinnedMessages,
                            onDismissReply: () =>
                                setState(() => _replyingTo = null),
                            onLongPressMessage: (message) =>
                                _showMessageActions(
                                  conversation: selected,
                                  message: message,
                                ),
                          )
                        : const Center(
                            child: Text(
                              'No conversations selected',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                  ),
                ],
              );
            }

            if (_showMobileChat && selected != null) {
              return _ChatPanel(
                conversation: selected,
                onBack: () => _setMobileConversationView(false),
                messageController: _composerController,
                onSend: () => _sendCurrentMessage(selected),
                isSending: _isSending,
                replyingTo: _replyingTo,
                pinnedMessages: pinnedMessages,
                onDismissReply: () => setState(() => _replyingTo = null),
                onLongPressMessage: (message) => _showMessageActions(
                  conversation: selected,
                  message: message,
                ),
              );
            }

            return _InboxPanel(
              conversations: _conversations,
              filters: _filters,
              selectedFilter: _selectedFilter,
              selectedIndex: _selectedConversation,
              onFilterSelected: _onFilterSelected,
              onConversationSelected: (index) =>
                  _onConversationSelected(index, openMobile: true),
              searchQuery: _searchQuery,
              onSearchChanged: (q) => setState(() => _searchQuery = q),
              pinnedChats: _pinnedChats,
              onPinToggled: _togglePin,
              isLoading: _isLoading,
            );
          },
        ),
      ),
    );
  }
}

class _InboxPanel extends StatelessWidget {
  final List<_Conversation> conversations;
  final List<String> filters;
  final int selectedFilter;
  final int selectedIndex;
  final ValueChanged<int> onFilterSelected;
  final ValueChanged<int> onConversationSelected;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Set<int> pinnedChats;
  final ValueChanged<int> onPinToggled;
  final bool isLoading;

  const _InboxPanel({
    required this.conversations,
    required this.filters,
    required this.selectedFilter,
    required this.selectedIndex,
    required this.onFilterSelected,
    required this.onConversationSelected,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.pinnedChats,
    required this.onPinToggled,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: filters.length,
      initialIndex: selectedFilter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF3F0FF)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Row(
                children: [
                  _HeaderIconButton(
                    icon: Icons.menu_rounded,
                    onTap: () {},
                    compact: true,
                  ),
                  const Expanded(
                    child: Text(
                      'Inbox',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF1A2340),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _HeaderIconButton(
                    icon: Icons.notifications_none_rounded,
                    onTap: () {},
                    filled: true,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: TextField(
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TabBar(
              onTap: onFilterSelected,
              labelColor: const Color(0xFF7A54FF),
              unselectedLabelColor: const Color(0xFF98A2B7),
              tabs: filters.map((f) => Tab(text: f)).toList(),
            ),
            Expanded(
              child: isLoading && conversations.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF7A54FF),
                      ),
                    )
                  : conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'No conversations found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: conversations.length,
                      separatorBuilder: (_, index) =>
                          Container(height: 1, color: const Color(0xFFE8E1FF)),
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final isPinned = pinnedChats.contains(conversation.id);
                        final hasUnread = conversation.messages.any(
                          (m) => !m.isMine && m.readAt == null,
                        );
                        return GestureDetector(
                          onLongPress: () => onPinToggled(conversation.id),
                          child: InkWell(
                            onTap: () => onConversationSelected(index),
                            child: Container(
                              color: index == selectedIndex
                                  ? const Color(0xFFF7F3FF)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _AvatarBubble(
                                    name: conversation.name,
                                    colors: conversation.avatarColors,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (isPinned)
                                              const Icon(
                                                Icons.push_pin,
                                                size: 14,
                                                color: Color(0xFF7A54FF),
                                              ),
                                            if (isPinned)
                                              const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                conversation.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color:
                                                      conversation
                                                          .accentNameColor ??
                                                      const Color(0xFF19213C),
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              conversation.timeAgo,
                                              style: const TextStyle(
                                                color: Color(0xFFA6B0C7),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        if (conversation.badge != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1EBFF),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0xFFD8CBFF),
                                              ),
                                            ),
                                            child: Text(
                                              conversation.badge!,
                                              style: const TextStyle(
                                                color: Color(0xFF6E4CFF),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        Text(
                                          conversation.preview,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF53627E),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    children: [
                                      if (conversation.item != null)
                                        _ItemThumb(item: conversation.item!),
                                      if (hasUnread) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF7A54FF),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPanel extends StatefulWidget {
  final _Conversation conversation;
  final VoidCallback? onBack;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final bool isSending;
  final _Message? replyingTo;
  final List<_Message> pinnedMessages;
  final VoidCallback onDismissReply;
  final ValueChanged<_Message> onLongPressMessage;

  const _ChatPanel({
    required this.conversation,
    required this.onBack,
    required this.messageController,
    required this.onSend,
    required this.isSending,
    required this.replyingTo,
    required this.pinnedMessages,
    required this.onDismissReply,
    required this.onLongPressMessage,
  });

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _showEmojiKeyboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToLatest();
    });
  }

  @override
  void didUpdateWidget(covariant _ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chatChanged = oldWidget.conversation.id != widget.conversation.id;
    final messageCountChanged =
        oldWidget.conversation.messages.length !=
        widget.conversation.messages.length;
    if (chatChanged || messageCountChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLatest(animated: !chatChanged);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _toggleEmojiKeyboard() {
    if (_showEmojiKeyboard) {
      setState(() => _showEmojiKeyboard = false);
      _inputFocusNode.requestFocus();
      return;
    }
    _inputFocusNode.unfocus();
    setState(() => _showEmojiKeyboard = true);
  }

  void _showPinnedMessagesSheet() {
    if (widget.pinnedMessages.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.pinnedMessages.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final msg = widget.pinnedMessages[index];
              return ListTile(
                leading: const Icon(
                  Icons.push_pin_rounded,
                  color: Color(0xFF7A54FF),
                ),
                title: Text(
                  msg.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(msg.time),
              );
            },
          ),
        );
      },
    );
  }

  void _scrollToLatest({bool animated = false}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F2FF)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                if (widget.onBack != null) ...[
                  _HeaderIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: widget.onBack!,
                    compact: true,
                  ),
                  const SizedBox(width: 6),
                ],
                _AvatarBubble(
                  name: widget.conversation.name,
                  colors: widget.conversation.avatarColors,
                  size: 54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.conversation.name,
                        style: const TextStyle(
                          color: Color(0xFF1A2340),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFF32C965),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.conversation.status,
                            style: const TextStyle(
                              color: Color(0xFF925AFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.conversation.item != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE6D9FF)),
                    ),
                    child: _ItemThumb(
                      item: widget.conversation.item!,
                      size: 48,
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE7DFFF)),
          if (widget.pinnedMessages.isNotEmpty)
            InkWell(
              onTap: _showPinnedMessagesSheet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                color: const Color(0xFFF3EEFF),
                child: Row(
                  children: [
                    const Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: Color(0xFF7A54FF),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.pinnedMessages.first.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4A3C7A),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.pinnedMessages.length}',
                      style: const TextStyle(
                        color: Color(0xFF7A54FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                children: [
                  const Text(
                    'TODAY',
                    style: TextStyle(
                      color: Color(0xFFC18EFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  ...widget.conversation.messages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final message = entry.value;
                    final showOffer =
                        widget.conversation.offer != null && index == 1;
                    return Column(
                      children: [
                        _MessageBubble(
                          message: message,
                          onLongPress: () => widget.onLongPressMessage(message),
                        ),
                        if (showOffer) ...[
                          const SizedBox(height: 18),
                          _OfferCard(offer: widget.conversation.offer!),
                          const SizedBox(height: 18),
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          Container(height: 1, color: const Color(0xFFE7DFFF)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              children: [
                if (widget.replyingTo != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EEFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0D0FF)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.reply_rounded,
                          size: 16,
                          color: Color(0xFF7A54FF),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.replyingTo!.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF5D4A8A),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: widget.onDismissReply,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF7A54FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFDCCFFF)),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFFB58DFF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFF),
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(color: const Color(0xFFE4EAF5)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: widget.messageController,
                                focusNode: _inputFocusNode,
                                onTap: () {
                                  if (_showEmojiKeyboard) {
                                    setState(() => _showEmojiKeyboard = false);
                                  }
                                },
                                onSubmitted: (_) => widget.onSend(),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF9AABCA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                style: TextStyle(
                                  color: Color(0xFF1A2340),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _toggleEmojiKeyboard,
                              icon: const Icon(
                                Icons.sentiment_satisfied_alt_outlined,
                                color: Color(0xFF90A1C3),
                                size: 30,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: widget.isSending ? null : widget.onSend,
                      borderRadius: BorderRadius.circular(29),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF935FFF), Color(0xFF6D2DF5)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF7E57FF,
                              ).withValues(alpha: 0.34),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: widget.isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 29,
                              ),
                      ),
                    ),
                  ],
                ),
                if (_showEmojiKeyboard)
                  SizedBox(
                    height: 280,
                    child: EmojiPicker(
                      textEditingController: widget.messageController,
                      onEmojiSelected: (_, emoji) {},
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _Message message;
  final VoidCallback onLongPress;

  const _MessageBubble({required this.message, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final bubble = InkWell(
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: message.isMine ? null : Colors.white,
          gradient: message.isMine
              ? const LinearGradient(
                  colors: [Color(0xFF9B68FF), Color(0xFF7D41FF)],
                )
              : null,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF161A2B).withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.replyToText != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: message.isMine
                      ? Colors.white.withValues(alpha: 0.14)
                      : const Color(0xFFF4EEFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  message.replyToText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: message.isMine
                        ? Colors.white
                        : const Color(0xFF5E4C8D),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                color: message.isMine ? Colors.white : const Color(0xFF24314D),
                fontSize: 16,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: message.isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          bubble,
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.time}${message.editedAt != null ? ' · edited' : ''}',
                  style: const TextStyle(
                    color: Color(0xFFA5B0C7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (message.isMine) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.done_all_rounded,
                    size: 16,
                    color: message.readAt == null
                        ? const Color(0xFFA5B0C7)
                        : const Color(0xFF2D8CFF),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final _OfferCardData offer;

  const _OfferCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDECFFF), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E57FF).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                Text(
                  offer.title,
                  style: const TextStyle(
                    color: Color(0xFF6F45FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.handshake_outlined,
                  color: Color(0xFF7A54FF),
                  size: 22,
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE9DCFF)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Offer Amount',
                        style: TextStyle(
                          color: Color(0xFF7F8CA7),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        offer.amount,
                        style: const TextStyle(
                          color: Color(0xFF18213C),
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                const _OfferButton(
                  label: 'Decline',
                  foreground: Color(0xFF42526E),
                  background: Color(0xFFF0F3F8),
                ),
                const SizedBox(width: 10),
                const _OfferButton(
                  label: 'Accept',
                  foreground: Colors.white,
                  background: Color(0xFF793BFF),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF97A5C1),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  offer.status,
                  style: const TextStyle(
                    color: Color(0xFF97A5C1),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferButton extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;

  const _OfferButton({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool compact;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: compact ? 44 : 56,
        height: compact ? 44 : 56,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFF1E9FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: const Color(0xFF7A54FF), size: 30),
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  final String name;
  final List<Color> colors;
  final double size;

  const _AvatarBubble({
    required this.name,
    required this.colors,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final parts = name.split(' ');
    final initials = parts.length > 1
        ? '${parts.first[0]}${parts.last[0]}'
        : name.substring(0, 1);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: const Color(0xFFE6DDFF), width: 2),
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFF1B2543),
            fontSize: size * 0.3,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  final _ItemPreview item;
  final double size;

  const _ItemThumb({required this.item, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: item.colors,
        ),
        border: Border.all(color: const Color(0xFFE7E2F5)),
      ),
      child: Icon(item.icon, color: Colors.white, size: size * 0.52),
    );
  }
}

class _Conversation {
  final int id;
  final String name;
  final ChatThread? chatThread;
  final String status;
  final String? badge;
  final String timeAgo;
  final String preview;
  final List<Color> avatarColors;
  final _ItemPreview? item;
  final List<_Message> messages;
  final _OfferCardData? offer;
  final Color? accentNameColor;

  const _Conversation({
    required this.id,
    this.chatThread,
    required this.name,
    required this.status,
    required this.badge,
    required this.timeAgo,
    required this.preview,
    required this.avatarColors,
    required this.item,
    required this.messages,
    this.offer,
    this.accentNameColor,
  });

  _Conversation copyWith({
    List<_Message>? messages,
    String? preview,
    String? timeAgo,
  }) {
    return _Conversation(
      id: id,
      chatThread: chatThread,
      name: name,
      status: status,
      badge: badge,
      timeAgo: timeAgo ?? this.timeAgo,
      preview: preview ?? this.preview,
      avatarColors: avatarColors,
      item: item,
      messages: messages ?? this.messages,
      offer: offer,
      accentNameColor: accentNameColor,
    );
  }
}

class _ItemPreview {
  final IconData icon;
  final List<Color> colors;

  const _ItemPreview({required this.icon, required this.colors});
}

class _Message {
  final int id;
  final String text;
  final String time;
  final bool isMine;
  final int senderId;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final int? replyToMessageId;
  final String? replyToText;

  const _Message({
    required this.id,
    required this.text,
    required this.time,
    required this.isMine,
    required this.senderId,
    required this.createdAt,
    this.readAt,
    this.editedAt,
    this.deletedAt,
    this.replyToMessageId,
    this.replyToText,
  });

  bool get isLocal => id < 0;
}

class _OfferCardData {
  final String title;
  final String amount;
  final String status;

  const _OfferCardData({
    required this.title,
    required this.amount,
    required this.status,
  });
}
