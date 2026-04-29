import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/ai_message.dart';
import '../../models/ai_pinned_message.dart';
import '../../models/chat_message.dart';
import '../../models/chat_pinned_message.dart';
import '../../models/chat_thread.dart';
import '../../repositories/ai_messages_repository.dart';
import '../../repositories/users_repository.dart';
import '../../services/ai_chat_service.dart';
import '../../services/chat_service.dart';
import '../../services/supabase_service.dart';

class InboxViewModel extends ChangeNotifier {
  InboxViewModel({
    ChatService? chatService,
    AiMessagesRepository? aiMessagesRepository,
    UsersRepository? usersRepository,
    AiChatService? aiChatService,
    String? Function()? authUserIdProvider,
  }) : _usersRepository = usersRepository ?? UsersRepository(),
       _chatService =
           chatService ??
           ChatService(
             usersRepository: usersRepository ?? UsersRepository(),
             authUserIdProvider:
                 authUserIdProvider ?? _defaultAuthUserIdProvider,
             appUserIdResolver: (authUserId) async {
               try {
                 final user = await (usersRepository ?? UsersRepository())
                     .getById(authUserId);
                 return user?.id ?? authUserId;
               } catch (_) {
                 return authUserId;
               }
             },
           ),
       _aiMessagesRepository = aiMessagesRepository ?? AiMessagesRepository(),
       _aiChatService = aiChatService ?? AiChatService(),
       _authUserIdProvider = authUserIdProvider ?? _defaultAuthUserIdProvider;

  final ChatService _chatService;
  final AiMessagesRepository _aiMessagesRepository;
  final UsersRepository _usersRepository;
  final AiChatService _aiChatService;
  final String? Function() _authUserIdProvider;

  bool _isLoadingInbox = false;
  bool _isDisposed = false;
  bool get isLoadingInbox => _isLoadingInbox;

  String? _cachedCurrentUserId;
  String? _cachedAuthUserId;

  String? get currentUserId =>
      _chatService.currentUserId ?? _cachedCurrentUserId;

  @override
  void notifyListeners() {
    // 3. 重写此方法：只有在未销毁时才通知 UI
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<List<ChatThread>> loadInbox() async {
    if (_isDisposed) {
      return const <ChatThread>[];
    }
    _setLoading(true);
    try {
      final inbox = await _chatService.loadInbox();
      _cachedCurrentUserId = _chatService.currentUserId;
      return inbox;
    } finally {
      _setLoading(false);
    }
  }

  Stream<List<ChatMessage>> watchMessages(int chatId) {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return _chatService.watchMessages(chatId);
  }

  Stream<List<AiMessage>> watchAiMessages() {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return _aiMessagesRepository.watchMessages();
  }

  Future<void> sendChatMessage({
    required int chatId,
    required String content,
  }) async {
    if (_isDisposed) {
      return;
    }
    final normalized = _requireNonEmptyContent(content);
    await _chatService.sendMessage(chatId: chatId, content: normalized);
  }

  Future<void> sendAiMessage(String text, {String? promptForAi}) {
    return _aiChatService.sendMessage(text, promptForAi: promptForAi);
  }

  Future<void> markChatAsRead(int chatId) {
    if (_isDisposed) {
      return Future.value();
    }
    return _chatService.markChatAsRead(chatId);
  }

  Future<Map<int, int>> loadUnreadCountsByChat(List<int> chatIds) {
    if (_isDisposed || chatIds.isEmpty) {
      return Future.value(const <int, int>{});
    }
    return _chatService.unreadCountsByChat(chatIds);
  }

  Future<Set<int>> loadPinnedConversationIds() {
    if (_isDisposed) {
      return Future.value(const <int>{});
    }
    return _chatService.listPinnedConversationIds();
  }

  Future<List<int>> loadPinnedConversationIdsOrdered() {
    if (_isDisposed) {
      return Future.value(const <int>[]);
    }
    return _chatService.listPinnedConversationIdsOrdered();
  }

  Future<void> setConversationPinned({
    required int chatId,
    required bool isPinned,
  }) {
    if (_isDisposed) {
      return Future.value();
    }
    return _chatService.setConversationPinned(
      chatId: chatId,
      isPinned: isPinned,
    );
  }

  Future<void> editChatMessage({
    required int messageId,
    required String content,
  }) async {
    if (_isDisposed) {
      return;
    }
    final normalized = _requireNonEmptyContent(content);
    await _chatService.editMessage(messageId: messageId, content: normalized);
  }

  Future<void> editAiMessage({
    required int messageId,
    required String content,
  }) {
    return _aiMessagesRepository.editMessage(
      messageId: messageId,
      content: content,
    );
  }

  Future<void> deleteChatMessage(int messageId) {
    if (_isDisposed) {
      return Future.value();
    }
    return _chatService.deleteMessage(messageId);
  }

  Future<void> deleteAiMessage(int messageId) {
    return _aiMessagesRepository.deleteMessage(messageId);
  }

  Future<void> pinChatMessage({required int chatId, required int messageId}) {
    if (_isDisposed) {
      return Future.value();
    }
    return _chatService.pinMessage(chatId: chatId, messageId: messageId);
  }

  Future<void> clearPinnedChatMessage({
    required int chatId,
    required int messageId,
  }) {
    if (_isDisposed) {
      return Future.value();
    }
    return _chatService.clearPinnedMessage(
      chatId: chatId,
      messageId: messageId,
    );
  }

  Future<List<ChatPinnedMessage>> listPinnedChatMessages(int chatId) {
    if (_isDisposed) {
      return Future.value(const <ChatPinnedMessage>[]);
    }
    return _chatService.listPinnedMessages(chatId);
  }

  Future<void> pinAiMessage(int messageId) {
    return _aiMessagesRepository.pinMessage(messageId);
  }

  Future<void> unpinAiMessage(int messageId) {
    return _aiMessagesRepository.unpinMessage(messageId);
  }

  Future<List<AiPinnedMessage>> listPinnedAiMessages() {
    return _aiMessagesRepository.listPinnedMessages();
  }

  Future<List<AiMessage>> fetchAiMessages() {
    return _aiMessagesRepository.fetchMessages();
  }

  Future<void> ensureAiConversationInitialized() {
    return _aiMessagesRepository.ensureConversationInitialized();
  }

  RealtimeChannel subscribeInboxChanges({required void Function() onChange}) {
    if (_isDisposed) {
      throw StateError('InboxViewModel is disposed.');
    }
    return _chatService.subscribeInboxChanges(onChange: onChange);
  }

  Future<void> unsubscribeInboxChanges(RealtimeChannel channel) {
    if (_isDisposed) {
      return Future.value();
    }
    return _chatService.unsubscribeInboxChanges(channel);
  }

  Future<String?> refreshCurrentUserId() async {
    final authUserId = _authUserIdProvider();
    if (authUserId == null || authUserId.isEmpty) {
      _cachedAuthUserId = null;
      _cachedCurrentUserId = null;
      return null;
    }

    if (_cachedAuthUserId == authUserId && _cachedCurrentUserId != null) {
      return _cachedCurrentUserId;
    }

    _cachedAuthUserId = authUserId;

    try {
      final user = await _usersRepository.getById(authUserId);
      _cachedCurrentUserId = user?.id ?? authUserId;
    } catch (_) {
      _cachedCurrentUserId = authUserId;
    }

    return _cachedCurrentUserId;
  }

  String _requireNonEmptyContent(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'content', 'Message cannot be empty.');
    }
    return normalized;
  }

  void _setLoading(bool value) {
    if (_isDisposed) {
      return;
    }
    if (_isLoadingInbox == value) {
      return;
    }
    _isLoadingInbox = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_chatService.dispose());
    super.dispose();
  }

  static String? _defaultAuthUserIdProvider() {
    if (!SupabaseService.isConfigured) {
      return null;
    }

    try {
      return SupabaseService.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }
}
