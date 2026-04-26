import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path_util;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/app_user.dart';
import '../../../models/chat_message.dart';
import '../../../models/chat_pinned_message.dart';
import '../../../models/chat_thread.dart';
import '../../../models/ai_message.dart';
import '../../../models/ai_pinned_message.dart';
import '../../../models/transaction.dart';
import '../../../repositories/items_repository.dart';
import '../../../repositories/payments_repository.dart';
import '../../../repositories/transactions_repository.dart';
import '../../../repositories/users_repository.dart';
import '../../../services/notification_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/chat_media_cache_service.dart';
import '../../../models/checkout_flow_kind.dart';
import '../../../models/meetup_address_option.dart';
import '../../../views/screens/transaction/checkout_screen.dart';
import '../../../views/screens/notifications/notifications_screen.dart';
import '../../../views/screens/item/item_detail_screen.dart';
import '../../../views/screens/profile/transaction_detail_screen.dart';
import '../../../viewmodels/chat/inbox_viewmodel.dart';
import '../../../repositories/local/local_messages_repository.dart';
import '../../../core/utils/app_snack_bars.dart';

class InboxScreen extends StatefulWidget {
  final ValueChanged<bool>? onConversationViewChanged;
  final int? focusConversationId;
  final ValueChanged<int>? onFocusConversationHandled;

  const InboxScreen({
    super.key,
    this.onConversationViewChanged,
    this.focusConversationId,
    this.onFocusConversationHandled,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  static const _mediaPrefix = '[[media]]';
  static const _ragItemsPrefix = '[[rag_items_json]]';
  static const _chatMediaBucket = 'chat-media';

  int _selectedFilter = 0;
  int _selectedConversation = 0;
  bool _showMobileChat = false;
  bool _isLoading = true;
  String _searchQuery = '';
  List<String> _recentSearchQueries = const [];
  Set<int> _pinnedChats = {};
  Set<int> _manuallyUnreadChats = {};
  Set<int> _hiddenChats = {};

  final InboxViewModel _inboxViewModel = InboxViewModel();
  dynamic _inboxSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  StreamSubscription<List<AiMessage>>? _aiMessagesSubscription;
  Timer? _inboxSubscriptionRetryTimer;
  bool _isLoadingInboxData = false;
  int? _activeChatId;
  final Map<int, List<ChatMessage>> _rawMessagesByChat = {};
  final Map<int, List<_Message>> _messagesByChat = {};
  final Map<int, List<ChatPinnedMessage>> _chatPins = {};
  final TextEditingController _composerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  _Message? _replyingTo;
  bool _isSending = false;
  bool _isRecordingVoice = false;
  DateTime? _voiceRecordingStartAt;
  String? _voiceDraftPath;
  String? _voiceDraftFileName;
  int? _voiceDraftDurationSeconds;
  bool _hasAttemptedAiConversationInit = false;
  int _unreadNotificationCount = 0;
  int? _lastAppliedFocusConversationId;

  String? get _currentUserId => _inboxViewModel.currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConversationPrefs();
    if (SupabaseService.isConfigured) {
      _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
        (_) => _handleUserChanged(),
      );
    }
    _loadInbox();
    _ensureInboxRealtimeSubscription();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusConversationId != widget.focusConversationId) {
      _tryFocusConversationFromExternalRequest();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inboxSubscriptionRetryTimer?.cancel();
    _authSubscription?.cancel();
    _messagesSubscription?.cancel();
    _aiMessagesSubscription?.cancel();
    if (_inboxSubscription != null) {
      _inboxViewModel.unsubscribeInboxChanges(_inboxSubscription);
    }
    _composerController.dispose();
    NotificationService.instance.setActiveChatContext(
      isConversationOpen: false,
    );
    unawaited(_audioRecorder.dispose());
    _inboxViewModel.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    NotificationService.instance.setActiveChatContext(
      isConversationOpen: false,
    );
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverRealtimeAfterResume());
    }
  }

  Future<void> _recoverRealtimeAfterResume() async {
    if (!mounted) {
      return;
    }

    try {
      if (_inboxSubscription != null) {
        await _inboxViewModel.unsubscribeInboxChanges(_inboxSubscription);
        _inboxSubscription = null;
      }
    } catch (_) {
      _inboxSubscription = null;
    }

    _ensureInboxRealtimeSubscription();

    // Rebind selected chat stream to avoid stale realtime listeners after
    // app background/foreground transitions.
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _aiMessagesSubscription?.cancel();
    _aiMessagesSubscription = null;
    _activeChatId = null;
    _subscribeToSelectedConversationMessages();

    await _loadInbox(force: true);
  }

  void _handleUserChanged() {
    _inboxSubscriptionRetryTimer?.cancel();
    if (_inboxSubscription != null) {
      unawaited(_inboxViewModel.unsubscribeInboxChanges(_inboxSubscription));
      _inboxSubscription = null;
    }
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _aiMessagesSubscription?.cancel();
    _aiMessagesSubscription = null;
    _activeChatId = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedConversation = 0;
      _showMobileChat = false;
      _isLoading = true;
      _replyingTo = null;
      _hasAttemptedAiConversationInit = false;
      _rawMessagesByChat.clear();
      _messagesByChat.clear();
      _chatPins.clear();
    });
    _composerController.clear();
    _loadInbox();
    _ensureInboxRealtimeSubscription();
  }

  void _ensureInboxRealtimeSubscription() {
    if (_inboxSubscription != null) {
      return;
    }
    unawaited(_ensureInboxRealtimeSubscriptionAsync());
  }

  Future<void> _ensureInboxRealtimeSubscriptionAsync() async {
    if (_inboxSubscription != null || !mounted) {
      return;
    }

    try {
      await _inboxViewModel.refreshCurrentUserId();
      if (!mounted || _inboxSubscription != null) {
        return;
      }
      _inboxSubscription = _inboxViewModel.subscribeInboxChanges(
        onChange: _loadInbox,
      );
      _inboxSubscriptionRetryTimer?.cancel();
      _inboxSubscriptionRetryTimer = null;
    } catch (_) {
      _scheduleInboxSubscriptionRetry();
    }
  }

  void _scheduleInboxSubscriptionRetry() {
    if (_inboxSubscriptionRetryTimer != null || !mounted) {
      return;
    }
    _inboxSubscriptionRetryTimer = Timer(const Duration(seconds: 2), () {
      _inboxSubscriptionRetryTimer = null;
      _ensureInboxRealtimeSubscription();
    });
  }

  Future<void> _loadInbox({bool force = true}) async {
    if (_isLoadingInboxData && !force) {
      return;
    }
    if (_isLoadingInboxData && force) {
      return;
    }
    _isLoadingInboxData = true;
    try {
      final threads = await _inboxViewModel.loadInbox();
      final unreadCountsByChat = await _inboxViewModel.loadUnreadCountsByChat(
        threads.map((thread) => thread.id).toList(growable: false),
      );
      _refreshUnreadNotificationCount();
      _ensureInboxRealtimeSubscription();
      final currentUserId = _currentUserId;
      final mapped = threads.map((t) {
        final itemTitle = (t.itemTitle ?? '').trim();
        final itemPreview = itemTitle.isEmpty
            ? null
            : _ItemPreview(
                title: itemTitle,
                imageUrl: t.itemImageUrls.isNotEmpty
                    ? t.itemImageUrls.first
                    : null,
                icon: Icons.inventory_2_rounded,
                colors: const [Color(0xFFB58AFF), Color(0xFF7A54FF)],
              );
        return _Conversation(
          id: t.id,
          chatThread: t,
          name: currentUserId == null
              ? (t.user2Name ?? t.user1Name ?? 'User')
              : t.otherUserName(currentUserId),
          avatarUrl: currentUserId == null
              ? null
              : t.otherUserProfileImage(currentUserId),
          status: 'Active',
          badge: null,
          timeAgo: _formatTime(t.updatedAt),
          unreadCount: unreadCountsByChat[t.id] ?? 0,
          preview: t.lastMessage == null
              ? 'No messages yet'
              : _parseMessageBody(
                  _parseReplyMetadata(t.lastMessage!).messageText,
                ).previewText,
          avatarColors: const [Color(0xFFE7DFFF), Color(0xFFC18EFF)],
          item: itemPreview,
          messages: _messagesByChat[t.id] ?? const [],
        );
      }).toList();

      final aiChat = _Conversation(
        id: -1,
        chatThread: null,
        name: 'Swaply Buddy',
        avatarUrl: null,
        status: 'Online',
        badge: 'AI',
        timeAgo: 'Always',
        unreadCount: 0,
        preview: 'Your AI assistant',
        avatarColors: const [Color(0xFF6D2DF5), Color(0xFF935FFF)],
        item: null,
        messages: _messagesByChat[-1] ?? const [],
        accentNameColor: const Color(0xFF7A54FF),
      );

      if (mounted) {
        setState(() {
          _allConversations.clear();
          _allConversations.add(aiChat);
          _allConversations.addAll(mapped);
          if (_selectedConversation >= _allConversations.length) {
            _selectedConversation = 0;
          }
          _isLoading = false;
        });
      }
      unawaited(_initializeAiConversationIfNeeded());
      _tryFocusConversationFromExternalRequest();
      _subscribeToSelectedConversationMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint('Error loading inbox: $e');
    } finally {
      _isLoadingInboxData = false;
    }
  }

  Future<void> _initializeAiConversationIfNeeded() async {
    if (_hasAttemptedAiConversationInit) {
      return;
    }

    if (!SupabaseService.isConfigured ||
        SupabaseService.client.auth.currentUser == null) {
      return;
    }

    _hasAttemptedAiConversationInit = true;

    try {
      await _inboxViewModel.ensureAiConversationInitialized();
      if (!mounted) {
        return;
      }

      await _refreshAiMessagesNow();
      await _loadPinnedMessagesForAiChat();
    } catch (e) {
      debugPrint('Error initializing AI conversation: $e');
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
    final unreadRaw = prefs.getStringList('manual_unread_chats') ?? [];
    final hiddenRaw = prefs.getStringList('hidden_chats') ?? [];
    final searchRaw = prefs.getStringList('chat_search_history') ?? [];
    setState(() {
      _pinnedChats = pinned;
      _manuallyUnreadChats = unreadRaw
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
      _hiddenChats = hiddenRaw.map(int.tryParse).whereType<int>().toSet();
      _recentSearchQueries = searchRaw;
    });
  }

  Future<void> _loadConversationPrefs() => _loadPinned();

  Future<void> _saveConversationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'pinned_chats',
      _pinnedChats.map((id) => id.toString()).toList(),
    );
    await prefs.setStringList(
      'manual_unread_chats',
      _manuallyUnreadChats.map((id) => id.toString()).toList(),
    );
    await prefs.setStringList(
      'hidden_chats',
      _hiddenChats.map((id) => id.toString()).toList(),
    );
    await prefs.setStringList('chat_search_history', _recentSearchQueries);
  }

  Future<void> _recordSearchQuery(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }

    setState(() {
      _recentSearchQueries = [
        normalized,
        ..._recentSearchQueries.where(
          (q) => q.toLowerCase() != normalized.toLowerCase(),
        ),
      ].take(12).toList();
    });
    await _saveConversationPrefs();
  }

  Future<void> _openNotificationsScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    await _refreshUnreadNotificationCount();
  }

  Future<void> _openConversationItemDetails(_Conversation conversation) async {
    final itemId = conversation.chatThread?.itemId;
    if (itemId == null) {
      return;
    }

    try {
      final authUser = SupabaseService.client.auth.currentUser;
      AppUser? currentUser;
      if (authUser != null) {
        currentUser = await UsersRepository().getById(authUser.id);
      }
      final item = await ItemsRepository().getById(itemId);
      if (!mounted || item == null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ItemDetailsScreen(loginUser: currentUser, item: item),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open item details.')),
      );
    }
  }

  Future<void> _refreshUnreadNotificationCount() async {
    try {
      final count = await NotificationService.instance.unreadCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _unreadNotificationCount = count;
      });
    } catch (_) {}
  }

  Future<void> _togglePin(int id) async {
    setState(() {
      if (_pinnedChats.contains(id)) {
        _pinnedChats.remove(id);
      } else {
        _pinnedChats.add(id);
      }
    });
    await _saveConversationPrefs();
  }

  Future<void> _toggleManualUnread(int id) async {
    setState(() {
      if (_manuallyUnreadChats.contains(id)) {
        _manuallyUnreadChats.remove(id);
      } else {
        _manuallyUnreadChats.add(id);
      }
    });
    await _saveConversationPrefs();
  }

  Future<void> _hideConversationForCurrentUser(int id) async {
    setState(() {
      _hiddenChats.add(id);
      _pinnedChats.remove(id);
      _manuallyUnreadChats.remove(id);
      if (_selectedConversation >= _conversations.length - 1) {
        _selectedConversation = 0;
      }
      _showMobileChat = false;
    });
    await _saveConversationPrefs();
  }

  Future<void> _showConversationActions(_Conversation conversation) async {
    final isPinned = _pinnedChats.contains(conversation.id);
    final isManualUnread = _manuallyUnreadChats.contains(conversation.id);
    final canDeleteConversation = conversation.id != -1;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.search_rounded),
                title: const Text('Search in this chat'),
                onTap: () {
                  Navigator.pop(context);
                  _openSearchDialog(focusConversationId: conversation.id);
                },
              ),
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(
                  isPinned ? 'Unpin conversation' : 'Pin conversation',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _togglePin(conversation.id);
                },
              ),
              ListTile(
                leading: Icon(
                  isManualUnread
                      ? Icons.mark_email_read_outlined
                      : Icons.mark_email_unread_outlined,
                ),
                title: Text(isManualUnread ? 'Mark as read' : 'Mark as unread'),
                onTap: () async {
                  Navigator.pop(context);
                  await _toggleManualUnread(conversation.id);
                },
              ),
              if (canDeleteConversation)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Clear chat history (only for you)'),
                  subtitle: const Text('The other user will keep this chat.'),
                  onTap: () async {
                    Navigator.pop(context);
                    final confirmed = await showDialog<bool>(
                      context: this.context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Clear this chat for you?'),
                          content: const Text(
                            'This only hides the conversation on your side. The other user is not affected.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        );
                      },
                    );

                    if (confirmed == true) {
                      await _hideConversationForCurrentUser(conversation.id);
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  List<_SearchMatch> _buildSearchMatches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }

    final matches = <_SearchMatch>[];
    for (final conversation in _allConversations) {
      if (_hiddenChats.contains(conversation.id)) {
        continue;
      }

      String? snippet;
      if (conversation.preview.toLowerCase().contains(normalized)) {
        snippet = conversation.preview;
      }

      for (final message in conversation.messages.reversed) {
        final text = message.text.toLowerCase();
        if (text.contains(normalized)) {
          snippet = message.text;
          break;
        }
      }

      if (snippet != null) {
        matches.add(
          _SearchMatch(
            conversationId: conversation.id,
            conversationName: conversation.name,
            snippet: snippet,
          ),
        );
      }
    }
    return matches;
  }

  void _selectConversationById(int conversationId, {bool openMobile = false}) {
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx == -1) {
      return;
    }
    _onConversationSelected(idx, openMobile: openMobile);
  }

  void _tryFocusConversationFromExternalRequest() {
    final requestedId = widget.focusConversationId;
    if (requestedId == null || requestedId <= 0) {
      return;
    }
    if (_lastAppliedFocusConversationId == requestedId) {
      return;
    }

    final idx = _conversations.indexWhere((c) => c.id == requestedId);
    if (idx == -1) {
      return;
    }

    _lastAppliedFocusConversationId = requestedId;
    _onConversationSelected(idx, openMobile: true);
    widget.onFocusConversationHandled?.call(requestedId);
  }

  Future<void> _openSearchDialog({int? focusConversationId}) async {
    final controller = TextEditingController(text: _searchQuery);
    final result = await showDialog<_SearchDialogResult>(
      context: context,
      builder: (context) {
        var localQuery = controller.text.trim();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final results = _buildSearchMatches(localQuery);
            final history = _recentSearchQueries;

            return AlertDialog(
              backgroundColor: const Color(0xFFFCFAFF),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Search chats'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE6DBFF)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF7A54FF,
                            ).withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search by user or message',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: Color(0xFF7A54FF),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            localQuery = value.trim();
                          });
                        },
                        onSubmitted: (value) {
                          final query = value.trim();
                          Navigator.pop(
                            context,
                            _SearchDialogResult(query: query),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (history.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Recent searches',
                              style: TextStyle(
                                color: Color(0xFF6B56A5),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemBuilder: (context, index) {
                                final h = history[index];
                                return InkWell(
                                  onTap: () {
                                    final historyMatches = _buildSearchMatches(
                                      h,
                                    );
                                    if (historyMatches.isNotEmpty) {
                                      Navigator.pop(
                                        context,
                                        _SearchDialogResult(
                                          query: h,
                                          conversationId: historyMatches
                                              .first
                                              .conversationId,
                                        ),
                                      );
                                      return;
                                    }

                                    controller.text = h;
                                    controller.selection =
                                        TextSelection.fromPosition(
                                          TextPosition(offset: h.length),
                                        );
                                    setDialogState(() {
                                      localQuery = h;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFE7FF),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFFE0D1FF),
                                      ),
                                    ),
                                    child: Text(
                                      h,
                                      style: const TextStyle(
                                        color: Color(0xFF5D3FC2),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemCount: history.length,
                            ),
                          ),
                        ],
                      ),
                    if (history.isNotEmpty) const SizedBox(height: 10),
                    Flexible(
                      child: results.isEmpty
                          ? const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'No matching chat history found.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: results.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final item = results[index];
                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      Navigator.pop(
                                        context,
                                        _SearchDialogResult(
                                          query: localQuery,
                                          conversationId: item.conversationId,
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFF1EBFF),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.history_rounded,
                                              size: 18,
                                              color: Color(0xFF7A54FF),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.conversationName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF2A2550),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.snippet,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF6B6791),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    const _SearchDialogResult(query: ''),
                  ),
                  child: const Text('Clear'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _SearchDialogResult(query: controller.text.trim()),
                  ),
                  child: const Text('Search'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _searchQuery = result.query;
      _selectedConversation = 0;
    });

    if (result.query.isNotEmpty) {
      await _recordSearchQuery(result.query);
    }

    if (result.conversationId != null) {
      _selectConversationById(result.conversationId!, openMobile: true);
    } else if (focusConversationId != null) {
      _selectConversationById(focusConversationId, openMobile: true);
    }
  }

  static const _filters = ['All', 'Selling', 'Buying'];

  final List<_Conversation> _allConversations = [];

  List<_Conversation> get _conversations {
    List<_Conversation> filtered = _allConversations.where((conv) {
      if (_hiddenChats.contains(conv.id)) {
        return false;
      }

      final matchesSearch =
          conv.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          conv.preview.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      if (conv.id == -1) {
        return true; // AI Chat should bypass Selling/Buying filters
      }

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
    final selected = _conversations[index];
    setState(() {
      _selectedConversation = index;
      _replyingTo = null;
      _manuallyUnreadChats.remove(selected.id);
      _voiceDraftPath = null;
      _voiceDraftFileName = null;
      _voiceDraftDurationSeconds = null;
    });
    unawaited(_saveConversationPrefs());
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
      _aiMessagesSubscription?.cancel();
      _aiMessagesSubscription = null;
      _activeChatId = null;
      return;
    }

    if (_activeChatId == selected.id &&
        (_messagesSubscription != null || _aiMessagesSubscription != null)) {
      return;
    }

    if (selected.id == -1) {
      _loadPinnedMessagesForAiChat();
    } else {
      _loadPinnedMessagesForChat(selected.id);
    }

    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _aiMessagesSubscription?.cancel();
    _aiMessagesSubscription = null;
    _activeChatId = selected.id;

    if (selected.id > 0) {
      bool isWide = false;
      try {
        isWide = MediaQuery.sizeOf(context).width >= 950;
      } catch (_) {}

      if (isWide || _showMobileChat) {
        _inboxViewModel.markChatAsRead(selected.id).catchError((_) {});
      }
    }

    if (selected.id == -1) {
      _aiMessagesSubscription = _inboxViewModel.watchAiMessages().listen(
        (aiMessages) {
          if (!mounted) return;
          _applyAiMessages(aiMessages);
        },
        onError: (e) {
          debugPrint('Error in AI message stream: $e');
        },
      );
    } else {
      _messagesSubscription = _inboxViewModel
          .watchMessages(selected.id)
          .listen(
            (messages) {
              if (!mounted) {
                return;
              }
              final messageById = {for (final m in messages) m.id: m};
              final uiMessages = messages
                  .map(
                    (m) => _toUiMessage(message: m, messageById: messageById),
                  )
                  .toList();

              final hasUnreadIncoming = messages.any(
                (m) => m.senderId != _currentUserId && m.readAt == null,
              );
              final unreadIncomingCount = messages
                  .where(
                    (m) => m.senderId != _currentUserId && m.readAt == null,
                  )
                  .length;

              bool isWide = false;
              try {
                isWide = MediaQuery.sizeOf(context).width >= 950;
              } catch (_) {}
              final isViewingChat = isWide || _showMobileChat;

              if (hasUnreadIncoming && isViewingChat) {
                _inboxViewModel.markChatAsRead(selected.id).catchError((_) {});
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
                    unreadCount: unreadIncomingCount,
                  );
                }
              });
            },
            onError: (error) {
              debugPrint('Error watching messages: $error');
            },
          );
    }
  }

  Future<void> _loadPinnedMessagesForChat(int chatId) async {
    try {
      final pins = await _inboxViewModel.listPinnedChatMessages(chatId);
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

  Future<void> _loadPinnedMessagesForAiChat() async {
    try {
      final pins = await _inboxViewModel.listPinnedAiMessages();
      if (!mounted) {
        return;
      }
      setState(() {
        _chatPins[-1] = pins
            .map(
              (AiPinnedMessage pin) => ChatPinnedMessage(
                chatId: -1,
                messageId: pin.messageId,
                pinnedAt: pin.pinnedAt,
              ),
            )
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading AI pinned messages: $e');
    }
  }

  _Message _toUiMessage({
    required ChatMessage message,
    required Map<int, ChatMessage> messageById,
  }) {
    final parsed = _parseReplyMetadata(message.content);
    final body = _parseMessageBody(parsed.messageText);
    final replied = parsed.repliedMessageId == null
        ? null
        : messageById[parsed.repliedMessageId!];

    final local = message.createdAt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    final replyText = replied == null
        ? null
        : _parseMessageBody(
            _parseReplyMetadata(replied.content).messageText,
          ).previewText;

    return _Message(
      id: message.id,
      text: body.displayText,
      media: body.media,
      cachedMediaPath: message.cachedMediaPath,
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

  _Message _toUiAiMessage({
    required AiMessage message,
    required Map<int, AiMessage> messageById,
  }) {
    final parsed = _parseReplyMetadata(message.content);
    final ragParsed = _parseAiRagItems(parsed.messageText);
    final body = _parseMessageBody(ragParsed.visibleText);
    final replied = parsed.repliedMessageId == null
        ? null
        : messageById[parsed.repliedMessageId!];

    final replyText = replied == null
        ? null
        : _parseMessageBody(
            _parseAiRagItems(
              _parseReplyMetadata(replied.content).messageText,
            ).visibleText,
          ).previewText;

    final local = message.createdAt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    return _Message(
      id: message.id,
      text: body.displayText,
      media: body.media,
      cachedMediaPath: null,
      time: '$hour:$minute $suffix',
      isMine: !message.isAi,
      senderId: message.userId,
      createdAt: message.createdAt,
      readAt: message.createdAt,
      editedAt: null,
      deletedAt: null,
      replyToMessageId: parsed.repliedMessageId,
      replyToText: replyText,
      ragItems:
          _shouldRenderAiRagItems(
            visibleText: ragParsed.visibleText,
            items: ragParsed.items,
          )
          ? ragParsed.items
          : const [],
    );
  }

  bool _shouldRenderAiRagItems({
    required String visibleText,
    required List<_AiRagItem> items,
  }) {
    if (items.isEmpty) {
      return false;
    }

    final text = visibleText.trim().toLowerCase();
    if (text.isEmpty) {
      return false;
    }

    // Suppress cards for generic small-talk/help replies.
    const genericPhrases = <String>[
      'how can i help',
      'i\'m here to assist',
      'hello',
      'hi there',
      'welcome',
      'how can i assist',
      'what can i do for you',
    ];
    for (final phrase in genericPhrases) {
      if (text.contains(phrase)) {
        return false;
      }
    }

    // Show cards when the AI indicates listing search/recommendation context.
    const listingSignals = <String>[
      'found',
      'listing',
      'listings',
      'recommend',
      'recommended',
      'match',
      'matches',
      'available',
      'priced at',
      'view this listing',
      'proceed with it',
    ];
    for (final signal in listingSignals) {
      if (text.contains(signal)) {
        return true;
      }
    }

    return false;
  }

  ({String visibleText, List<_AiRagItem> items}) _parseAiRagItems(
    String content,
  ) {
    final markerIndex = content.indexOf(_ragItemsPrefix);
    if (markerIndex == -1) {
      return (visibleText: content.trim(), items: const []);
    }

    final visibleText = content.substring(0, markerIndex).trimRight();
    final rawPayload = content
        .substring(markerIndex + _ragItemsPrefix.length)
        .trim();

    if (rawPayload.isEmpty) {
      return (visibleText: visibleText, items: const []);
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! List) {
        return (visibleText: visibleText, items: const []);
      }

      final ragItems = <_AiRagItem>[];
      for (final entry in decoded) {
        if (entry is! Map) {
          continue;
        }

        final map = entry.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );

        final itemIdRaw = map['id'];
        final itemId = itemIdRaw is num
            ? itemIdRaw.toInt()
            : int.tryParse(itemIdRaw?.toString() ?? '');
        final title = map['title']?.toString().trim() ?? '';

        if (itemId == null || title.isEmpty) {
          continue;
        }

        final priceValue = map['price'];
        final price =
            (priceValue == null || priceValue.toString().trim().isEmpty)
            ? null
            : priceValue.toString();

        ragItems.add(
          _AiRagItem(
            id: itemId,
            title: title,
            price: price,
            listingType: map['listing_type']?.toString(),
            condition: map['condition']?.toString(),
            category: map['category']?.toString(),
          ),
        );
      }

      return (visibleText: visibleText, items: ragItems);
    } catch (_) {
      return (visibleText: visibleText, items: const []);
    }
  }

  void _applyAiMessages(List<AiMessage> aiMessages) {
    final messageById = {for (final m in aiMessages) m.id: m};
    final mappedMessages = aiMessages
        .map((m) => _toUiAiMessage(message: m, messageById: messageById))
        .toList();

    setState(() {
      _messagesByChat[-1] = mappedMessages;
      final index = _allConversations.indexWhere((c) => c.id == -1);
      if (index >= 0) {
        _allConversations[index] = _allConversations[index].copyWith(
          messages: mappedMessages,
          preview: mappedMessages.isNotEmpty
              ? mappedMessages.last.text
              : 'Your AI assistant',
          timeAgo: mappedMessages.isNotEmpty ? 'Just now' : 'Always',
        );
      }
    });
  }

  Future<void> _refreshAiMessagesNow() async {
    try {
      final aiMessages = await _inboxViewModel.fetchAiMessages();
      if (!mounted) {
        return;
      }
      _applyAiMessages(aiMessages);
    } catch (e) {
      debugPrint('Error refreshing AI messages: $e');
    }
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

  _ParsedMessageBody _parseMessageBody(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith(_mediaPrefix)) {
      return _ParsedMessageBody.text(trimmed);
    }

    final jsonRaw = trimmed.substring(_mediaPrefix.length).trimLeft();
    if (jsonRaw.isEmpty) {
      return _ParsedMessageBody.text(trimmed);
    }

    try {
      final decoded = jsonDecode(jsonRaw);
      if (decoded is! Map) {
        return _ParsedMessageBody.text(trimmed);
      }

      final map = decoded.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final typeValue = map['type']?.toString().trim().toLowerCase();
      final urlValue = map['url']?.toString().trim();
      if (typeValue == null || typeValue.isEmpty) {
        return _ParsedMessageBody.text(trimmed);
      }
      if (urlValue == null || urlValue.isEmpty) {
        return _ParsedMessageBody.text(trimmed);
      }

      final type = _MessageMediaType.fromWire(typeValue);
      if (type == null) {
        return _ParsedMessageBody.text(trimmed);
      }

      final name = map['name']?.toString().trim();
      final durationSeconds = map['duration_seconds'] is num
          ? (map['duration_seconds'] as num).toInt()
          : int.tryParse(map['duration_seconds']?.toString() ?? '');
      final caption = map['caption']?.toString().trim();
      final itemIdRaw = map['item_id'];
      final itemId = itemIdRaw is num
          ? itemIdRaw.toInt()
          : int.tryParse(itemIdRaw?.toString() ?? '');
      final offeredItemIdRaw = map['offered_item_id'];
      final offeredItemId = offeredItemIdRaw is num
          ? offeredItemIdRaw.toInt()
          : int.tryParse(offeredItemIdRaw?.toString() ?? '');
      final transactionIdRaw = map['transaction_id'];
      final transactionId = transactionIdRaw is num
          ? transactionIdRaw.toInt()
          : int.tryParse(transactionIdRaw?.toString() ?? '');
      final buyerId = map['buyer_id']?.toString().trim();
      final sellerId = map['seller_id']?.toString().trim();
      final media = _MessageMedia(
        type: type,
        url: urlValue,
        fileName: name == null || name.isEmpty ? null : name,
        durationSeconds: durationSeconds,
        caption: caption == null || caption.isEmpty ? null : caption,
        itemId: itemId,
        offeredItemId: offeredItemId,
        transactionId: transactionId,
        buyerId: buyerId == null || buyerId.isEmpty ? null : buyerId,
        sellerId: sellerId == null || sellerId.isEmpty ? null : sellerId,
      );
      return _ParsedMessageBody.media(media);
    } catch (_) {
      return _ParsedMessageBody.text(trimmed);
    }
  }

  String _encodeMediaMessage(_MessageMedia media) {
    final payload = <String, dynamic>{
      'type': media.type.wireValue,
      'url': media.url,
      if (media.fileName != null) 'name': media.fileName,
      if (media.durationSeconds != null)
        'duration_seconds': media.durationSeconds,
      if (media.caption != null) 'caption': media.caption,
      if (media.itemId != null) 'item_id': media.itemId,
      if (media.offeredItemId != null) 'offered_item_id': media.offeredItemId,
      if (media.transactionId != null) 'transaction_id': media.transactionId,
      if (media.buyerId != null) 'buyer_id': media.buyerId,
      if (media.sellerId != null) 'seller_id': media.sellerId,
    };
    return '$_mediaPrefix${jsonEncode(payload)}';
  }

  Future<String?> _uploadAttachment({
    required _Conversation conversation,
    required File file,
    required _MessageMediaType type,
    required String contentType,
    required String fileName,
  }) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return null;
    }

    final ext = path_util
        .extension(fileName)
        .replaceFirst('.', '')
        .toLowerCase();
    final safeExt = ext.isEmpty ? _fallbackExtensionFor(type: type) : ext;
    final baseName = path_util.basenameWithoutExtension(fileName).trim().isEmpty
        ? type.wireValue
        : path_util.basenameWithoutExtension(fileName);
    final sanitizedName = baseName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final objectPath =
        'chat/${conversation.id}/user_$currentUserId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName.$safeExt';

    final bucket = SupabaseService.client.storage.from(_chatMediaBucket);
    await bucket.upload(
      objectPath,
      file,
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );
    return bucket.getPublicUrl(objectPath);
  }

  String _fallbackExtensionFor({required _MessageMediaType type}) {
    switch (type) {
      case _MessageMediaType.image:
        return 'jpg';
      case _MessageMediaType.voice:
        return 'm4a';
      case _MessageMediaType.document:
        return 'bin';
    }
  }

  String _guessImageContentType(String fileName) {
    final ext = path_util.extension(fileName).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  bool _canModifyMessage(_Message message) {
    if (!message.isMine ||
        message.deletedAt != null ||
        message.isLocal ||
        message.media != null) {
      return false;
    }
    return DateTime.now().difference(message.createdAt) <=
        const Duration(minutes: 3);
  }

  Future<void> _showMessageActions({
    required _Conversation conversation,
    required _Message message,
  }) async {
    final isAiConversation = conversation.id == -1;
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
                  final copied = message.media?.url ?? message.text;
                  Clipboard.setData(ClipboardData(text: copied));
                },
              ),
              if (canModify)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _editMessage(conversation, message);
                  },
                ),
              if (canModify)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(conversation, message);
                  },
                ),
              if (canPin)
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(isPinned ? 'Unpin' : 'Pin'),
                  onTap: () {
                    Navigator.pop(context);
                    if (isPinned) {
                      if (isAiConversation) {
                        _unpinAiMessage(message);
                      } else {
                        _unpinMessage(conversation, message);
                      }
                    } else {
                      if (isAiConversation) {
                        _pinAiMessage(message);
                      } else {
                        _pinMessage(conversation, message);
                      }
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

  Future<void> _editMessage(
    _Conversation conversation,
    _Message message,
  ) async {
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
      if (conversation.id == -1) {
        await _inboxViewModel.editAiMessage(
          messageId: message.id,
          content: updatedText,
        );
        await _refreshAiMessagesNow();
      } else {
        await _inboxViewModel.editChatMessage(
          messageId: message.id,
          content: updatedText,
        );
      }
    } catch (e) {
      debugPrint('Error editing message: $e');
    }
  }

  Future<void> _deleteMessage(
    _Conversation conversation,
    _Message message,
  ) async {
    if (message.isLocal) {
      return;
    }

    try {
      if (conversation.id == -1) {
        await _inboxViewModel.deleteAiMessage(message.id);
        await _unpinAiMessage(message);
        await _refreshAiMessagesNow();
      } else {
        await _inboxViewModel.deleteChatMessage(message.id);
      }
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  Future<void> _pinMessage(_Conversation conversation, _Message message) async {
    if (message.isLocal) {
      return;
    }

    try {
      await _inboxViewModel.pinChatMessage(
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
      await _inboxViewModel.clearPinnedChatMessage(
        chatId: conversation.id,
        messageId: message.id,
      );
      await _loadPinnedMessagesForChat(conversation.id);
      await _loadInbox();
    } catch (e) {
      debugPrint('Error clearing pin: $e');
    }
  }

  Future<void> _pinAiMessage(_Message message) async {
    if (message.isLocal) {
      return;
    }

    try {
      await _inboxViewModel.pinAiMessage(message.id);
      await _loadPinnedMessagesForAiChat();
    } catch (e) {
      debugPrint('Error pinning AI message: $e');
    }
  }

  Future<void> _unpinAiMessage(_Message message) async {
    if (message.isLocal) {
      return;
    }

    try {
      await _inboxViewModel.unpinAiMessage(message.id);
      await _loadPinnedMessagesForAiChat();
    } catch (e) {
      debugPrint('Error unpinning AI message: $e');
    }
  }

  void _showSnack(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendQuickMessage(
    _Conversation conversation,
    String text, {
    String? promptForAi,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) {
      return;
    }

    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final suffix = now.hour >= 12 ? 'PM' : 'AM';
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return;
    }
    final parsedBody = _parseMessageBody(trimmed);

    final optimistic = _Message(
      id: -now.microsecondsSinceEpoch,
      text: parsedBody.displayText,
      media: parsedBody.media,
      cachedMediaPath: null,
      time: '$hour:$minute $suffix',
      isMine: true,
      senderId: currentUserId,
      createdAt: now,
      readAt: null,
      editedAt: null,
      deletedAt: null,
    );

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
            preview: parsedBody.previewText,
            timeAgo: 'Just now',
          );
        }
      });

      if (conversation.id == -1) {
        await _inboxViewModel.sendAiMessage(
          trimmed,
          promptForAi: promptForAi ?? parsedBody.previewText,
        );
        await _refreshAiMessagesNow();
      } else {
        await _inboxViewModel.sendChatMessage(
          chatId: conversation.id,
          content: trimmed,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final existing = List<_Message>.from(
            _messagesByChat[conversation.id] ?? const [],
          );
          existing.removeWhere((m) => m.id == optimistic.id);
          _messagesByChat[conversation.id] = existing;
        });
      }
      debugPrint('Error sending quick message: $e');
      _showSnack('Unable to send message. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _sendGalleryPhoto(_Conversation conversation) async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (photo == null) {
        return;
      }
      final name = path_util.basename(photo.path);
      final uploadedUrl = await _uploadAttachment(
        conversation: conversation,
        file: File(photo.path),
        type: _MessageMediaType.image,
        contentType: _guessImageContentType(name),
        fileName: name,
      );
      if (uploadedUrl == null) {
        return;
      }

      final mediaMessage = _MessageMedia(
        type: _MessageMediaType.image,
        url: uploadedUrl,
        fileName: name,
      );
      await _sendQuickMessage(
        conversation,
        _encodeMediaMessage(mediaMessage),
        promptForAi: '[Photo] $name',
      );
    } catch (e) {
      debugPrint('Error picking gallery photo: $e');
      _showSnack(
        'Unable to send photo. Ensure Storage bucket "$_chatMediaBucket" exists and is public.',
      );
    }
  }

  Future<void> _sendCameraPhoto(_Conversation conversation) async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null) {
        return;
      }
      final name = path_util.basename(photo.path);
      final uploadedUrl = await _uploadAttachment(
        conversation: conversation,
        file: File(photo.path),
        type: _MessageMediaType.image,
        contentType: _guessImageContentType(name),
        fileName: name,
      );
      if (uploadedUrl == null) {
        return;
      }

      final mediaMessage = _MessageMedia(
        type: _MessageMediaType.image,
        url: uploadedUrl,
        fileName: name,
      );
      await _sendQuickMessage(
        conversation,
        _encodeMediaMessage(mediaMessage),
        promptForAi: '[Camera Photo] $name',
      );
    } catch (e) {
      debugPrint('Error taking camera photo: $e');
      _showSnack(
        'Unable to send photo. Ensure Storage bucket "$_chatMediaBucket" exists and is public.',
      );
    }
  }

  Future<void> _sendDocument(_Conversation conversation) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final picked = result.files.first;
      final localFile = await _materializePickedFile(picked);
      if (localFile == null) {
        _showSnack('Unable to read selected document.');
        return;
      }

      final name = picked.name.trim().isEmpty ? 'Document' : picked.name;
      final uploadedUrl = await _uploadAttachment(
        conversation: conversation,
        file: localFile,
        type: _MessageMediaType.document,
        contentType: _guessDocumentContentType(name),
        fileName: name,
      );
      if (uploadedUrl == null) {
        _showSnack('Unable to upload document.');
        return;
      }

      final mediaMessage = _MessageMedia(
        type: _MessageMediaType.document,
        url: uploadedUrl,
        fileName: name,
      );
      await _sendQuickMessage(
        conversation,
        _encodeMediaMessage(mediaMessage),
        promptForAi: '[Document] $name',
      );
    } catch (e) {
      debugPrint('Error picking document: $e');
      _showSnack('Unable to pick document.');
    }
  }

  Future<File?> _materializePickedFile(PlatformFile picked) async {
    final filePath = picked.path;
    if (filePath != null && filePath.trim().isNotEmpty) {
      final existing = File(filePath);
      if (await existing.exists()) {
        return existing;
      }
    }

    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final ext = path_util.extension(picked.name);
    final safeExt = ext.isEmpty ? '.bin' : ext;
    final outPath =
        '${Directory.systemTemp.path}/swaply_doc_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final file = File(outPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _guessDocumentContentType(String fileName) {
    final ext = path_util.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.txt':
        return 'text/plain';
      case '.csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String?> _promptManualLocationMessage() async {
    final latController = TextEditingController();
    final lngController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: latController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lngController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final lat = double.tryParse(latController.text.trim());
                final lng = double.tryParse(lngController.text.trim());
                if (lat == null || lng == null) {
                  return;
                }
                Navigator.of(context).pop(
                  '[Location] https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
                );
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
    latController.dispose();
    lngController.dispose();
    return result;
  }

  Future<void> _sendLocation(_Conversation conversation) async {
    final option = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.my_location_rounded),
                title: const Text('Send current location'),
                onTap: () => Navigator.of(context).pop('current'),
              ),
              ListTile(
                leading: const Icon(Icons.place_rounded),
                title: const Text('Choose location manually'),
                onTap: () => Navigator.of(context).pop('manual'),
              ),
            ],
          ),
        );
      },
    );

    if (option == null) {
      return;
    }

    if (option == 'manual') {
      final manualMessage = await _promptManualLocationMessage();
      if (manualMessage != null) {
        await _sendQuickMessage(conversation, manualMessage);
      }
      return;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Location service is disabled on this device.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location permission is required to share location.');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);
      await _sendQuickMessage(
        conversation,
        '[Location] https://maps.google.com/?q=$lat,$lng',
      );
    } catch (e) {
      debugPrint('Error fetching current location: $e');
      _showSnack('Unable to get current location.');
    }
  }

  Future<void> _startVoiceRecording() async {
    if (_isSending || _isRecordingVoice) {
      return;
    }
    try {
      final granted = await _audioRecorder.hasPermission();
      if (!granted) {
        _showSnack('Microphone permission is required for voice recording.');
        return;
      }

      final filePath =
          '${Directory.systemTemp.path}/swaply_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: filePath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = true;
        _voiceRecordingStartAt = DateTime.now();
        _voiceDraftPath = null;
        _voiceDraftFileName = null;
        _voiceDraftDurationSeconds = null;
      });
    } catch (e) {
      debugPrint('Error starting voice record: $e');
      _showSnack('Unable to start voice recording.');
    }
  }

  Future<void> _stopVoiceRecording() async {
    if (!_isRecordingVoice) {
      return;
    }

    final startedAt = _voiceRecordingStartAt;
    try {
      final recordPath = await _audioRecorder.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordingStartAt = null;
      });

      if (recordPath == null) {
        return;
      }

      final seconds = startedAt == null
          ? 1
          : DateTime.now().difference(startedAt).inSeconds.clamp(1, 3600);
      final fileName = path_util.basename(recordPath);
      setState(() {
        _voiceDraftPath = recordPath;
        _voiceDraftFileName = fileName;
        _voiceDraftDurationSeconds = seconds;
      });
    } catch (e) {
      debugPrint('Error stopping voice record: $e');
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _voiceRecordingStartAt = null;
          _voiceDraftPath = null;
          _voiceDraftFileName = null;
          _voiceDraftDurationSeconds = null;
        });
      }
      _showSnack('Unable to save voice recording.');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _discardVoiceDraft() async {
    final draftPath = _voiceDraftPath;
    setState(() {
      _voiceDraftPath = null;
      _voiceDraftFileName = null;
      _voiceDraftDurationSeconds = null;
    });

    if (draftPath == null || draftPath.trim().isEmpty) {
      return;
    }

    try {
      final file = File(draftPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _sendVoiceDraft(_Conversation conversation) async {
    final draftPath = _voiceDraftPath;
    if (draftPath == null || draftPath.trim().isEmpty || _isSending) {
      return;
    }

    final file = File(draftPath);
    if (!await file.exists()) {
      _showSnack('Voice draft is missing. Please record again.');
      await _discardVoiceDraft();
      return;
    }

    final fileName = _voiceDraftFileName ?? path_util.basename(draftPath);
    final seconds = (_voiceDraftDurationSeconds ?? 1).clamp(1, 3600);

    try {
      final uploadedUrl = await _uploadAttachment(
        conversation: conversation,
        file: file,
        type: _MessageMediaType.voice,
        contentType: 'audio/mp4',
        fileName: fileName,
      );
      if (uploadedUrl == null) {
        _showSnack('Unable to upload voice message.');
        return;
      }

      final mediaMessage = _MessageMedia(
        type: _MessageMediaType.voice,
        url: uploadedUrl,
        fileName: fileName,
        durationSeconds: seconds,
      );
      await _sendQuickMessage(
        conversation,
        _encodeMediaMessage(mediaMessage),
        promptForAi: '[Voice] $fileName (${seconds}s)',
      );
      await _discardVoiceDraft();
    } catch (e) {
      debugPrint('Error sending voice draft: $e');
      _showSnack('Unable to send voice message.');
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
      cachedMediaPath: null,
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

      if (conversation.id == -1) {
        await _inboxViewModel.sendAiMessage(payload, promptForAi: text);
        await _refreshAiMessagesNow();
      } else {
        await _inboxViewModel.sendChatMessage(
          chatId: conversation.id,
          content: payload,
        );
      }

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

    if (isOpen && _activeChatId != null && _activeChatId! > 0) {
      _inboxViewModel.markChatAsRead(_activeChatId!).catchError((_) {});
    }
  }

  void _syncShellChrome(bool isWide) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onConversationViewChanged?.call(!isWide && _showMobileChat);
      final hasChatOpen = isWide || _showMobileChat;
      final selected = _conversations.isNotEmpty
          ? _conversations[_selectedConversation < _conversations.length
                ? _selectedConversation
                : 0]
          : null;
      final activeChatId = hasChatOpen && selected != null && selected.id > 0
          ? selected.id
          : null;
      NotificationService.instance.setActiveChatContext(
        isConversationOpen: activeChatId != null,
        chatId: activeChatId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showMobileChat,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_showMobileChat) {
          _setMobileConversationView(false);
        }
      },
      child: Scaffold(
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
                        onSearchTap: _openSearchDialog,
                        onNotificationsTap: _openNotificationsScreen,
                        unreadNotificationCount: _unreadNotificationCount,
                        pinnedChats: _pinnedChats,
                        manuallyUnreadChats: _manuallyUnreadChats,
                        onPinToggled: _togglePin,
                        onConversationLongPress: _showConversationActions,
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
                              isAiConversation: selected.id == -1,
                              onDismissReply: () =>
                                  setState(() => _replyingTo = null),
                              onLongPressMessage: (message) =>
                                  _showMessageActions(
                                    conversation: selected,
                                    message: message,
                                  ),
                              onPickPhoto: () => _sendGalleryPhoto(selected),
                              onOpenCamera: () => _sendCameraPhoto(selected),
                              onShareLocation: () => _sendLocation(selected),
                              onPickDocument: () => _sendDocument(selected),
                              onVoiceRecordToggle: _toggleVoiceRecording,
                              isRecordingVoice: _isRecordingVoice,
                              voiceDraftPath: _voiceDraftPath,
                              voiceDraftDurationSeconds:
                                  _voiceDraftDurationSeconds,
                              onDeleteVoiceDraft: _discardVoiceDraft,
                              onSendVoiceDraft: () => _sendVoiceDraft(selected),
                              onUnpinPinnedMessage: (message) {
                                if (selected.id == -1) {
                                  _unpinAiMessage(message);
                                } else {
                                  _unpinMessage(selected, message);
                                }
                              },
                              isConversationPinned: _pinnedChats.contains(
                                selected.id,
                              ),
                              onOpenConversationMenu: () =>
                                  _showConversationActions(selected),
                              onOpenItemDetails: () =>
                                  _openConversationItemDetails(selected),
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
                  isAiConversation: selected.id == -1,
                  onDismissReply: () => setState(() => _replyingTo = null),
                  onLongPressMessage: (message) => _showMessageActions(
                    conversation: selected,
                    message: message,
                  ),
                  onPickPhoto: () => _sendGalleryPhoto(selected),
                  onOpenCamera: () => _sendCameraPhoto(selected),
                  onShareLocation: () => _sendLocation(selected),
                  onPickDocument: () => _sendDocument(selected),
                  onVoiceRecordToggle: _toggleVoiceRecording,
                  isRecordingVoice: _isRecordingVoice,
                  voiceDraftPath: _voiceDraftPath,
                  voiceDraftDurationSeconds: _voiceDraftDurationSeconds,
                  onDeleteVoiceDraft: _discardVoiceDraft,
                  onSendVoiceDraft: () => _sendVoiceDraft(selected),
                  onUnpinPinnedMessage: (message) {
                    if (selected.id == -1) {
                      _unpinAiMessage(message);
                    } else {
                      _unpinMessage(selected, message);
                    }
                  },
                  isConversationPinned: _pinnedChats.contains(selected.id),
                  onOpenConversationMenu: () =>
                      _showConversationActions(selected),
                  onOpenItemDetails: () =>
                      _openConversationItemDetails(selected),
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
                onSearchTap: _openSearchDialog,
                onNotificationsTap: _openNotificationsScreen,
                unreadNotificationCount: _unreadNotificationCount,
                pinnedChats: _pinnedChats,
                manuallyUnreadChats: _manuallyUnreadChats,
                onPinToggled: _togglePin,
                onConversationLongPress: _showConversationActions,
                isLoading: _isLoading,
              );
            },
          ),
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
  final VoidCallback onSearchTap;
  final Future<void> Function() onNotificationsTap;
  final int unreadNotificationCount;
  final Set<int> pinnedChats;
  final Set<int> manuallyUnreadChats;
  final ValueChanged<int> onPinToggled;
  final ValueChanged<_Conversation> onConversationLongPress;
  final bool isLoading;

  const _InboxPanel({
    required this.conversations,
    required this.filters,
    required this.selectedFilter,
    required this.selectedIndex,
    required this.onFilterSelected,
    required this.onConversationSelected,
    required this.searchQuery,
    required this.onSearchTap,
    required this.onNotificationsTap,
    required this.unreadNotificationCount,
    required this.pinnedChats,
    required this.manuallyUnreadChats,
    required this.onPinToggled,
    required this.onConversationLongPress,
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
                    icon: searchQuery.isEmpty
                        ? Icons.search_rounded
                        : Icons.search_off_rounded,
                    onTap: onSearchTap,
                    filled: true,
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _HeaderIconButton(
                        icon: Icons.notifications_none_rounded,
                        onTap: () {
                          onNotificationsTap();
                        },
                        filled: true,
                        compact: true,
                      ),
                      if (unreadNotificationCount > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              unreadNotificationCount > 99
                                  ? '99+'
                                  : unreadNotificationCount.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE6FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Searching: $searchQuery',
                      style: const TextStyle(
                        color: Color(0xFF5D3FC2),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                      padding: const EdgeInsets.only(bottom: 120, top: 8),
                      itemCount: conversations.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final selectedConversationId =
                            selectedIndex >= 0 &&
                                selectedIndex < conversations.length
                            ? conversations[selectedIndex].id
                            : null;
                        final isPinned = pinnedChats.contains(conversation.id);
                        final hasManualUnread = manuallyUnreadChats.contains(
                          conversation.id,
                        );
                        final unreadCount = conversation.unreadCount > 0
                            ? conversation.unreadCount
                            : (hasManualUnread ? 1 : 0);
                        final showUnreadBadge =
                            unreadCount > 0 &&
                            conversation.id != selectedConversationId;
                        return GestureDetector(
                          onLongPress: () =>
                              onConversationLongPress(conversation),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFF0EFFF),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF7A54FF,
                                  ).withValues(alpha: 0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: InkWell(
                              onTap: () => onConversationSelected(index),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _AvatarBubble(
                                      name: conversation.name,
                                      imageUrl: conversation.avatarUrl,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1EBFF),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFD8CBFF,
                                                  ),
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
                                          if (conversation.item != null) ...[
                                            const SizedBox(height: 7),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 9,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5F0FF),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFE1D2FF,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                'Item: ${conversation.item!.title}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Color(0xFF6A49C9),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      children: [
                                        if (conversation.item != null)
                                          _ItemThumb(item: conversation.item!),
                                        if (showUnreadBadge) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            constraints: const BoxConstraints(
                                              minWidth: 20,
                                              minHeight: 20,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF6441E8),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              unreadCount > 99
                                                  ? '99+'
                                                  : unreadCount.toString(),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
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
  final bool isAiConversation;
  final VoidCallback onDismissReply;
  final ValueChanged<_Message> onLongPressMessage;
  final ValueChanged<_Message> onUnpinPinnedMessage;
  final VoidCallback onPickPhoto;
  final VoidCallback onOpenCamera;
  final VoidCallback onShareLocation;
  final VoidCallback onPickDocument;
  final VoidCallback onVoiceRecordToggle;
  final bool isRecordingVoice;
  final String? voiceDraftPath;
  final int? voiceDraftDurationSeconds;
  final VoidCallback onDeleteVoiceDraft;
  final VoidCallback onSendVoiceDraft;
  final bool isConversationPinned;
  final VoidCallback onOpenConversationMenu;
  final VoidCallback onOpenItemDetails;

  const _ChatPanel({
    required this.conversation,
    required this.onBack,
    required this.messageController,
    required this.onSend,
    required this.isSending,
    required this.replyingTo,
    required this.pinnedMessages,
    required this.isAiConversation,
    required this.onDismissReply,
    required this.onLongPressMessage,
    required this.onUnpinPinnedMessage,
    required this.onPickPhoto,
    required this.onOpenCamera,
    required this.onShareLocation,
    required this.onPickDocument,
    required this.onVoiceRecordToggle,
    required this.isRecordingVoice,
    required this.voiceDraftPath,
    required this.voiceDraftDurationSeconds,
    required this.onDeleteVoiceDraft,
    required this.onSendVoiceDraft,
    required this.isConversationPinned,
    required this.onOpenConversationMenu,
    required this.onOpenItemDetails,
  });

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  AudioPlayer? _draftVoicePlayer;
  StreamSubscription<PlayerState>? _draftVoiceStateSub;
  bool _isPlayingVoiceDraft = false;
  String? _loadedVoiceDraftPath;
  bool _showEmojiKeyboard = false;
  bool _showAttachmentOptions = false;

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
    if (chatChanged && _showAttachmentOptions) {
      _showAttachmentOptions = false;
    }
    if (chatChanged || messageCountChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLatest(animated: !chatChanged);
      });
    }

    if (oldWidget.voiceDraftPath != widget.voiceDraftPath) {
      if (_isPlayingVoiceDraft) {
        unawaited(_draftVoicePlayer?.stop());
      }
      _isPlayingVoiceDraft = false;
      _loadedVoiceDraftPath = null;
    }
  }

  @override
  void dispose() {
    _draftVoiceStateSub?.cancel();
    unawaited(_draftVoicePlayer?.dispose());
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceDraftPlayback() async {
    final draftPath = widget.voiceDraftPath;
    if (draftPath == null || draftPath.trim().isEmpty) {
      return;
    }

    try {
      _draftVoicePlayer ??= AudioPlayer();
      _draftVoiceStateSub ??= _draftVoicePlayer!.playerStateStream.listen((
        state,
      ) {
        if (!mounted) {
          return;
        }
        final finished = state.processingState == ProcessingState.completed;
        setState(() {
          _isPlayingVoiceDraft = state.playing && !finished;
        });
        if (finished) {
          unawaited(_draftVoicePlayer!.seek(Duration.zero));
        }
      });

      if (_loadedVoiceDraftPath != draftPath) {
        await _draftVoicePlayer!.setFilePath(draftPath);
        _loadedVoiceDraftPath = draftPath;
      }

      if (_isPlayingVoiceDraft) {
        await _draftVoicePlayer!.pause();
      } else {
        await _draftVoicePlayer!.play();
      }
    } catch (_) {}
  }

  String _voiceDraftDurationLabel(int? seconds) {
    final value = (seconds ?? 0).clamp(0, 3600);
    final min = (value ~/ 60).toString().padLeft(2, '0');
    final sec = (value % 60).toString().padLeft(2, '0');
    return '$min:$sec';
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

  void _toggleAttachmentOptions() {
    if (_showEmojiKeyboard) {
      _showEmojiKeyboard = false;
      _inputFocusNode.unfocus();
    }
    setState(() => _showAttachmentOptions = !_showAttachmentOptions);
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
                trailing: IconButton(
                  tooltip: widget.isAiConversation
                      ? 'Unpin message'
                      : 'Unpin for both users',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onUnpinPinnedMessage(msg);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _scrollToLatest({bool animated = false}) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToLatest(animated: animated);
        }
      });
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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dayLabel(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final dayDiff = today.difference(messageDay).inDays;

    if (dayDiff == 0) {
      return 'TODAY';
    }
    if (dayDiff == 1) {
      return 'YESTERDAY';
    }

    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  List<Widget> _buildTimelineWidgets() {
    final widgets = <Widget>[];
    DateTime? lastDay;

    for (var index = 0; index < widget.conversation.messages.length; index++) {
      final message = widget.conversation.messages[index];
      final messageDay = message.createdAt.toLocal();

      if (lastDay == null || !_isSameDay(lastDay, messageDay)) {
        widgets.add(
          Text(
            _dayLabel(messageDay),
            style: const TextStyle(
              color: Color(0xFFC18EFF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        );
        widgets.add(const SizedBox(height: 22));
        lastDay = messageDay;
      }

      final showOffer =
          widget.conversation.offer != null &&
          index == 1 &&
          widget.conversation.id != -1;

      widgets.add(
        _MessageBubble(
          message: message,
          onLongPress: () => widget.onLongPressMessage(message),
        ),
      );

      if (showOffer) {
        widgets.add(const SizedBox(height: 18));
        widgets.add(_OfferCard(offer: widget.conversation.offer!));
        widgets.add(const SizedBox(height: 18));
      }
    }

    if (widgets.isEmpty) {
      widgets.add(
        const Text(
          'TODAY',
          style: TextStyle(
            color: Color(0xFFC18EFF),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      );
      widgets.add(const SizedBox(height: 22));
    }

    return widgets;
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
                  imageUrl: widget.conversation.avatarUrl,
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
                      if (widget.conversation.item != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Item: ${widget.conversation.item!.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF66509D),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.conversation.item != null)
                  InkWell(
                    onTap: widget.onOpenItemDetails,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
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
                  ),
                const SizedBox(width: 8),
                _HeaderIconButton(
                  icon: Icons.more_vert_rounded,
                  onTap: widget.onOpenConversationMenu,
                  filled: true,
                  compact: true,
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
              child: Column(children: _buildTimelineWidgets()),
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
                    InkWell(
                      onTap: _toggleAttachmentOptions,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFDCCFFF)),
                          color: _showAttachmentOptions
                              ? const Color(0xFFEDE3FF)
                              : Colors.transparent,
                        ),
                        child: Icon(
                          _showAttachmentOptions
                              ? Icons.close_rounded
                              : Icons.add_rounded,
                          color: const Color(0xFFB58DFF),
                        ),
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
                                  if (_showEmojiKeyboard ||
                                      _showAttachmentOptions) {
                                    setState(() {
                                      _showEmojiKeyboard = false;
                                      _showAttachmentOptions = false;
                                    });
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
                    GestureDetector(
                      onTap: widget.onVoiceRecordToggle,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isRecordingVoice
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFF1E9FF),
                        ),
                        child: Icon(
                          widget.isRecordingVoice
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: widget.isRecordingVoice
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF7A54FF),
                          size: 25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    widget.isRecordingVoice
                        ? 'Recording... tap mic again to stop'
                        : (widget.voiceDraftPath == null
                              ? ''
                              : 'Voice draft ready: preview, delete, or send'),
                    style: TextStyle(
                      color: widget.isRecordingVoice
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF8B95AC),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.voiceDraftPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
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
                          InkWell(
                            onTap: _toggleVoiceDraftPlayback,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFE7DBFF),
                              ),
                              child: Icon(
                                _isPlayingVoiceDraft
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: const Color(0xFF6D2DF5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Voice message ${_voiceDraftDurationLabel(widget.voiceDraftDurationSeconds)}',
                              style: const TextStyle(
                                color: Color(0xFF4E3F78),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onDeleteVoiceDraft,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFF8F4A4A),
                            ),
                            tooltip: 'Delete voice draft',
                          ),
                          FilledButton.icon(
                            onPressed: widget.isSending
                                ? null
                                : widget.onSendVoiceDraft,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6D2DF5),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(86, 38),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('Send'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_showAttachmentOptions)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.2,
                      children: [
                        _ComposerQuickAction(
                          icon: Icons.photo_library_outlined,
                          label: 'Photo',
                          onTap: widget.onPickPhoto,
                        ),
                        _ComposerQuickAction(
                          icon: Icons.camera_alt_outlined,
                          label: 'Camera',
                          onTap: widget.onOpenCamera,
                        ),
                        _ComposerQuickAction(
                          icon: Icons.location_on_outlined,
                          label: 'Location',
                          onTap: widget.onShareLocation,
                        ),
                        _ComposerQuickAction(
                          icon: Icons.description_outlined,
                          label: 'Document',
                          onTap: widget.onPickDocument,
                        ),
                      ],
                    ),
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

class _ComposerQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ComposerQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3D4FF)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7A54FF).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFF5EEFF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: const Color(0xFF7A54FF)),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF5A418B),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final _Message message;
  final VoidCallback onLongPress;

  const _MessageBubble({required this.message, required this.onLongPress});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  final LocalMessagesRepository _localMessagesRepository =
      LocalMessagesRepository();
  AudioPlayer? _audioPlayer;
  StreamSubscription<PlayerState>? _playerStateSub;
  bool _isPlaying = false;
  bool _isDownloadingDocument = false;
  String? _loadedUrl;

  _Message get message => widget.message;

  Future<void> _toggleVoice() async {
    final media = message.media;
    if (media == null || media.type != _MessageMediaType.voice) {
      return;
    }
    try {
      _audioPlayer ??= AudioPlayer();
      _playerStateSub ??= _audioPlayer!.playerStateStream.listen((state) {
        if (!mounted) {
          return;
        }
        final finished = state.processingState == ProcessingState.completed;
        setState(() {
          _isPlaying = state.playing && !finished;
        });
        if (finished) {
          unawaited(_audioPlayer!.seek(Duration.zero));
        }
      });

      if (_loadedUrl != media.url) {
        await _audioPlayer!.setUrl(media.url);
        _loadedUrl = media.url;
      }

      if (_isPlaying) {
        await _audioPlayer!.pause();
      } else {
        await _audioPlayer!.play();
      }
    } catch (_) {}
  }

  Future<void> _openDocumentAttachment(_MessageMedia media) async {
    final name = _resolveDocumentFileName(media);

    Future<bool> openUri(Uri uri) async {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    try {
      if (!_isDownloadingDocument) {
        final cachedPath = message.cachedMediaPath;
        if (cachedPath != null && cachedPath.trim().isNotEmpty) {
          final cached = await ChatMediaCacheService.instance.getCachedMedia(
            cachedPath,
          );
          if (cached != null) {
            final opened = await openUri(Uri.file(cached.path));
            if (!opened && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Unable to open cached file.')),
              );
            }
            return;
          }
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isDownloadingDocument = true;
      });

      final downloadedPath = await ChatMediaCacheService.instance
          .cacheMediaFromUrl(media.url, name);
      if (downloadedPath == null || downloadedPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to download file.')),
          );
        }
        return;
      }

      if (!message.isLocal) {
        await _localMessagesRepository.updateCachedMediaPath(
          messageId: message.id,
          cachedPath: downloadedPath,
        );
      }

      final opened = await openUri(Uri.file(downloadedPath));
      if (!opened) {
        await openUri(Uri.parse(media.url));
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to local cache: $name')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open document.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingDocument = false;
        });
      }
    }
  }

  String _resolveDocumentFileName(_MessageMedia media) {
    final fromPayload = media.fileName;
    if (fromPayload != null && fromPayload.trim().isNotEmpty) {
      return fromPayload.trim();
    }

    try {
      final uri = Uri.parse(media.url);
      final fromPath = path_util.basename(uri.path);
      if (fromPath.trim().isNotEmpty) {
        return fromPath.trim();
      }
    } catch (_) {}

    return 'document.bin';
  }

  Future<void> _openMediaItemDetails(_MessageMedia media) async {
    final itemId = media.itemId;
    if (itemId == null) {
      return;
    }

    try {
      final authUser = SupabaseService.client.auth.currentUser;
      AppUser? currentUser;
      if (authUser != null) {
        currentUser = await UsersRepository().getById(authUser.id);
      }
      final item = await ItemsRepository().getById(itemId);
      if (!mounted || item == null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ItemDetailsScreen(loginUser: currentUser, item: item),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open item details.')),
      );
    }
  }

  Future<void> _openTransactionDetails(_MessageMedia media) async {
    final txId = media.transactionId;
    if (txId == null) return;

    try {
      final authUser = SupabaseService.client.auth.currentUser;
      if (authUser == null) return;

      final viewer = await UsersRepository().getById(authUser.id);
      if (viewer == null || !mounted) return;

      final tx = await TransactionsRepository().getById(txId);
      if (tx == null || !mounted) return;

      final itemsRepo = ItemsRepository();
      final item = await itemsRepo.getById(tx.itemId);
      final tradedItem = tx.tradedItemId == null
          ? null
          : await itemsRepo.getById(tx.tradedItemId!);

      final seller = await UsersRepository().getById(tx.sellerId);
      final payments = await PaymentsRepository().listForTransaction(
        tx.transactionId,
      );
      final latestPayment = payments.isNotEmpty ? payments.first : null;

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(
            viewer: viewer,
            tx: tx,
            item: item,
            tradedItem: tradedItem,
            seller: seller,
            payment: latestPayment,
            isBuyer: tx.buyerId == viewer.id,
            onChanged: () {},
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open transaction details.')),
      );
    }
  }

  String _formatPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Price unavailable';
    }

    final normalized = value.trim().replaceAll(',', '');
    final parsed = double.tryParse(normalized);
    if (parsed == null) {
      return 'RM $value';
    }

    final hasFraction = parsed % 1 != 0;
    return hasFraction
        ? 'RM ${parsed.toStringAsFixed(2)}'
        : 'RM ${parsed.toStringAsFixed(0)}';
  }

  String _formatListingType(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'sell':
        return 'Sell';
      case 'trade':
        return 'Trade';
      case 'both':
        return 'Both';
      default:
        return value.isEmpty ? '' : value[0].toUpperCase() + value.substring(1);
    }
  }

  Widget _buildTag(String label) {
    if (label.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE5FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6F45FF),
        ),
      ),
    );
  }

  Widget _buildRagItemCard(_AiRagItem ragItem) {
    final listingType = _formatListingType(ragItem.listingType);
    final condition = (ragItem.condition ?? '').trim();
    final shortDescription = condition.isNotEmpty
        ? 'Condition: $condition'
        : (ragItem.category ?? '').trim();

    return Card(
      elevation: 2.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      shadowColor: const Color(0xFF7A54FF).withValues(alpha: 0.14),
      child: InkWell(
        //   onTap: () => _openRagItemDetails(ragItem),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      ragItem.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2740),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: Color(0xFF7A54FF),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatPrice(ragItem.price),
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF7A54FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (shortDescription.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  shortDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF5C6B89),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (listingType.isNotEmpty) _buildTag(listingType),
                  if (listingType.isNotEmpty && condition.isNotEmpty)
                    const SizedBox(width: 6),
                  if (condition.isNotEmpty) _buildTag(condition),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7A54FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'View Listing',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    unawaited(_audioPlayer?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Render as regular bubble (not full-width) if it has item_id (trade acceptance message)
    final hasItemLink = message.media?.itemId != null;
    final isImageOnly =
        message.media?.type == _MessageMediaType.image && !hasItemLink;
    final bubble = InkWell(
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(isImageOnly ? 18 : 22),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: isImageOnly
            ? const EdgeInsets.all(8)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: isImageOnly
              ? (message.isMine
                    ? const Color(0xFFF0E7FF)
                    : const Color(0xFFFAF8FF))
              : (message.isMine ? null : Colors.white),
          gradient: isImageOnly
              ? null
              : (message.isMine
                    ? const LinearGradient(
                        colors: [Color(0xFF9B68FF), Color(0xFF7D41FF)],
                      )
                    : null),
          border: isImageOnly
              ? Border.all(color: const Color(0xFFC4A1FF), width: 1.4)
              : null,
          borderRadius: BorderRadius.circular(isImageOnly ? 18 : 22),
          boxShadow: isImageOnly
              ? [
                  BoxShadow(
                    color: const Color(0xFF7A54FF).withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
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
            if (message.media != null) _buildMediaWidget(message.media!),
            if (message.media == null)
              Text(
                message.text,
                style: TextStyle(
                  color: message.isMine
                      ? Colors.white
                      : const Color(0xFF24314D),
                  fontSize: 16,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (message.media == null && message.ragItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Column(
                children: message.ragItems
                    .map<Widget>((ragItem) => _buildRagItemCard(ragItem))
                    .toList(),
              ),
            ],
            if (message.media?.caption != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isImageOnly
                      ? const Color(0xFFEFE5FF)
                      : (message.isMine
                            ? Colors.white.withValues(alpha: 0.16)
                            : const Color(0xFFF4EEFF)),
                  borderRadius: BorderRadius.circular(10),
                  border: isImageOnly
                      ? Border.all(color: const Color(0xFFCCB0FF))
                      : null,
                ),
                child: Text(
                  message.media!.caption!,
                  style: TextStyle(
                    color: isImageOnly
                        ? const Color(0xFF42206E)
                        : (message.isMine
                              ? Colors.white
                              : const Color(0xFF24314D)),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (message.media?.itemId != null) ...[
              const SizedBox(height: 10),
              _buildItemActionButtons(message.media!),
            ],
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

  Widget _buildMediaWidget(_MessageMedia media) {
    switch (media.type) {
      case _MessageMediaType.image:
        return InkWell(
          onTap: media.itemId == null
              ? null
              : () => _openMediaItemDetails(media),
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 280,
                    maxHeight: 280,
                  ),
                  child: Image.network(
                    media.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stackTrace) =>
                        _mediaErrorCard('Photo unavailable'),
                  ),
                ),
              ),
              if (media.itemId != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'View item',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      case _MessageMediaType.voice:
        return InkWell(
          onTap: _toggleVoice,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: message.isMine
                  ? Colors.white.withValues(alpha: 0.15)
                  : const Color(0xFFF4EEFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 28,
                  color: message.isMine
                      ? Colors.white
                      : const Color(0xFF7A54FF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    media.durationLabel,
                    style: TextStyle(
                      color: message.isMine
                          ? Colors.white
                          : const Color(0xFF24314D),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _MessageMediaType.document:
        return InkWell(
          onTap: _isDownloadingDocument
              ? null
              : () => _openDocumentAttachment(media),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: message.isMine
                  ? Colors.white.withValues(alpha: 0.15)
                  : const Color(0xFFF4EEFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.description_rounded,
                  size: 26,
                  color: message.isMine
                      ? Colors.white
                      : const Color(0xFF7A54FF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _resolveDocumentFileName(media),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: message.isMine
                              ? Colors.white
                              : const Color(0xFF24314D),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isDownloadingDocument
                            ? 'Downloading...'
                            : (message.cachedMediaPath == null
                                  ? 'Tap to download'
                                  : 'Tap to open cached file'),
                        style: TextStyle(
                          color: message.isMine
                              ? Colors.white.withValues(alpha: 0.92)
                              : const Color(0xFF5E6A87),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isDownloadingDocument)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF7A54FF),
                    ),
                  )
                else
                  Icon(
                    Icons.download_rounded,
                    size: 20,
                    color: message.isMine
                        ? Colors.white
                        : const Color(0xFF7A54FF),
                  ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildItemActionButtons(_MessageMedia media) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isBuyer = currentUserId != null && media.buyerId == currentUserId;
    final isSeller = currentUserId != null && media.sellerId == currentUserId;

    final canCancel =
        (isBuyer || isSeller) &&
        media.transactionId != null &&
        media.itemId != null &&
        media.offeredItemId != null;

    final canProceed =
        isBuyer &&
        media.transactionId != null &&
        media.itemId != null &&
        media.offeredItemId != null &&
        media.sellerId != null;

    final txId = media.transactionId;
    if (txId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Transaction?>(
      future: TransactionsRepository().getById(txId),
      builder: (context, snap) {
        final status = snap.data?.transactionStatus ?? 'pending';
        final showViewDetails = status != 'pending';

        if (showViewDetails) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _openTransactionDetails(media),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF7A54FF),
                padding: const EdgeInsets.symmetric(vertical: 11),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'View details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          );
        }

        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: !canCancel
                    ? null
                    : () async {
                        try {
                          await ItemsRepository().updateStatus(
                            'available',
                            media.itemId!,
                          );
                          await ItemsRepository().updateStatus(
                            isBuyer ? 'dropped' : 'rejected',
                            media.offeredItemId!,
                          );
                          await TransactionsRepository().updateStatus(
                            transactionId: media.transactionId!,
                            transactionStatus: 'cancelled',
                          );
                          if (!mounted) return;
                          AppSnackBars.success(context, 'Offer cancelled.');
                          setState(() {});
                        } catch (e) {
                          if (!mounted) return;
                          AppSnackBars.error(context, 'Cancel failed: $e');
                        }
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6F45FF),
                  side: const BorderSide(color: Color(0xFFB895FF), width: 1.4),
                  backgroundColor: const Color(0xFFF8F3FF),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (isBuyer) ...[
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: !canProceed
                      ? null
                      : () async {
                          try {
                            final item = await ItemsRepository().getById(
                              media.itemId!,
                            );
                            if (item == null) {
                              throw StateError('Item not found.');
                            }
                            final offered = await ItemsRepository().getById(
                              media.offeredItemId!,
                            );
                            if (offered == null) {
                              throw StateError('Offered item not found.');
                            }
                            final seller = await UsersRepository().getById(
                              media.sellerId!,
                            );
                            final meetups = MeetupAddressOption.fromSellerItem(
                              item,
                            );

                            if (!mounted) return;
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CheckoutScreen(
                                  flowKind: CheckoutFlowKind.swap,
                                  primaryItem: item,
                                  swapItem: offered,
                                  sellerDisplayName:
                                      seller?.username ?? 'Seller',
                                  sellerId: media.sellerId!,
                                  buyerId: currentUserId,
                                  sellerMeetupOptions: meetups,
                                  // trade: meet-up only, no payment
                                  tradeTransactionId: media.transactionId!,
                                  meetUpOnly: true,
                                  hidePaymentSection: true,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            setState(() {});
                          } catch (e) {
                            if (!mounted) return;
                            AppSnackBars.error(context, 'Proceed failed: $e');
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF10B981), // Green
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Proceed',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _mediaErrorCard(String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: message.isMine
            ? Colors.white.withValues(alpha: 0.15)
            : const Color(0xFFF4EEFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: message.isMine ? Colors.white : const Color(0xFF24314D),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
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
  final String? imageUrl;
  final List<Color> colors;
  final double size;

  const _AvatarBubble({
    required this.name,
    this.imageUrl,
    required this.colors,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final parts = name.split(' ');
    final initials = parts.length > 1
        ? '${parts.first[0]}${parts.last[0]}'
        : name.substring(0, 1);
    final normalizedImageUrl = imageUrl?.trim();
    final hasImage =
        normalizedImageUrl != null && normalizedImageUrl.isNotEmpty;

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
        child: ClipOval(
          child: hasImage
              ? Image.network(
                  normalizedImageUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Text(
                      initials.toUpperCase(),
                      style: TextStyle(
                        color: const Color(0xFF1B2543),
                        fontSize: size * 0.3,
                        fontWeight: FontWeight.w800,
                      ),
                    );
                  },
                )
              : Text(
                  initials.toUpperCase(),
                  style: TextStyle(
                    color: const Color(0xFF1B2543),
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.w800,
                  ),
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
    final imageUrl = item.imageUrl;
    final hasNetworkImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: hasNetworkImage
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: item.colors,
              ),
        border: Border.all(color: const Color(0xFFE7E2F5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: hasNetworkImage
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    item.icon,
                    color: Colors.white,
                    size: size * 0.52,
                  );
                },
              )
            : Icon(item.icon, color: Colors.white, size: size * 0.52),
      ),
    );
  }
}

class _Conversation {
  final int id;
  final String name;
  final ChatThread? chatThread;
  final String? avatarUrl;
  final String status;
  final String? badge;
  final String timeAgo;
  final int unreadCount;
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
    this.avatarUrl,
    required this.status,
    required this.badge,
    required this.timeAgo,
    required this.unreadCount,
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
    int? unreadCount,
  }) {
    return _Conversation(
      id: id,
      chatThread: chatThread,
      name: name,
      avatarUrl: avatarUrl,
      status: status,
      badge: badge,
      timeAgo: timeAgo ?? this.timeAgo,
      unreadCount: unreadCount ?? this.unreadCount,
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
  final String title;
  final String? imageUrl;
  final IconData icon;
  final List<Color> colors;

  const _ItemPreview({
    required this.title,
    this.imageUrl,
    required this.icon,
    required this.colors,
  });
}

class _ParsedMessageBody {
  final String displayText;
  final String previewText;
  final _MessageMedia? media;

  const _ParsedMessageBody({
    required this.displayText,
    required this.previewText,
    this.media,
  });

  factory _ParsedMessageBody.text(String text) {
    final normalized = text.trim();
    return _ParsedMessageBody(
      displayText: normalized,
      previewText: normalized.isEmpty ? 'Message' : normalized,
    );
  }

  factory _ParsedMessageBody.media(_MessageMedia media) {
    final label = media.caption ?? media.defaultLabel;
    return _ParsedMessageBody(
      displayText: label,
      previewText: label,
      media: media,
    );
  }
}

enum _MessageMediaType {
  image('image'),
  voice('voice'),
  document('document');

  final String wireValue;

  const _MessageMediaType(this.wireValue);

  static _MessageMediaType? fromWire(String value) {
    for (final type in _MessageMediaType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return null;
  }
}

class _MessageMedia {
  final _MessageMediaType type;
  final String url;
  final String? fileName;
  final int? durationSeconds;
  final String? caption;
  final int? itemId;
  final int? offeredItemId;
  final int? transactionId;
  final String? buyerId;
  final String? sellerId;

  const _MessageMedia({
    required this.type,
    required this.url,
    this.fileName,
    this.durationSeconds,
    this.caption,
    this.itemId,
    this.offeredItemId,
    this.transactionId,
    this.buyerId,
    this.sellerId,
  });

  String get defaultLabel {
    switch (type) {
      case _MessageMediaType.image:
        return 'Photo';
      case _MessageMediaType.voice:
        return 'Voice message';
      case _MessageMediaType.document:
        return 'Document';
    }
  }

  String get durationLabel {
    if (durationSeconds == null) {
      return defaultLabel;
    }
    return '$defaultLabel (${durationSeconds}s)';
  }
}

class _Message {
  final int id;
  final String text;
  final _MessageMedia? media;
  final String? cachedMediaPath;
  final String time;
  final bool isMine;
  final String senderId;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final int? replyToMessageId;
  final String? replyToText;
  final List<_AiRagItem> ragItems;

  const _Message({
    required this.id,
    required this.text,
    this.media,
    this.cachedMediaPath,
    required this.time,
    required this.isMine,
    required this.senderId,
    required this.createdAt,
    this.readAt,
    this.editedAt,
    this.deletedAt,
    this.replyToMessageId,
    this.replyToText,
    this.ragItems = const [],
  });

  bool get isLocal => id < 0;
}

class _AiRagItem {
  final int id;
  final String title;
  final String? price;
  final String? listingType;
  final String? condition;
  final String? category;

  const _AiRagItem({
    required this.id,
    required this.title,
    this.price,
    this.listingType,
    this.condition,
    this.category,
  });
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

class _SearchMatch {
  final int conversationId;
  final String conversationName;
  final String snippet;

  const _SearchMatch({
    required this.conversationId,
    required this.conversationName,
    required this.snippet,
  });
}

class _SearchDialogResult {
  final String query;
  final int? conversationId;

  const _SearchDialogResult({required this.query, this.conversationId});
}
