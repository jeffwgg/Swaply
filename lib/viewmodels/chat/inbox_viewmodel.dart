import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/ai_message.dart';
import '../../models/ai_pinned_message.dart';
import '../../models/chat_message.dart';
import '../../models/chat_pinned_message.dart';
import '../../models/chat_thread.dart';
import '../../repositories/ai_messages_repository.dart';
import '../../repositories/chats_repository.dart';
import '../../repositories/messages_repository.dart';
import '../../repositories/users_repository.dart';
import '../../services/ai_chat_service.dart';
import '../../services/supabase_service.dart';

class InboxViewModel extends ChangeNotifier {
  InboxViewModel({
    ChatsRepository? chatsRepository,
    MessagesRepository? messagesRepository,
    AiMessagesRepository? aiMessagesRepository,
    UsersRepository? usersRepository,
    AiChatService? aiChatService,
    String? Function()? authUserIdProvider,
  }) : _chatsRepository = chatsRepository ?? ChatsRepository(),
       _messagesRepository = messagesRepository ?? MessagesRepository(),
       _aiMessagesRepository = aiMessagesRepository ?? AiMessagesRepository(),
       _usersRepository = usersRepository ?? UsersRepository(),
       _aiChatService = aiChatService ?? AiChatService(),
       _authUserIdProvider = authUserIdProvider ?? _defaultAuthUserIdProvider;

  final ChatsRepository _chatsRepository;
  final MessagesRepository _messagesRepository;
  final AiMessagesRepository _aiMessagesRepository;
  final UsersRepository _usersRepository;
  final AiChatService _aiChatService;
  final String? Function() _authUserIdProvider;

  bool _isLoadingInbox = false;
  bool get isLoadingInbox => _isLoadingInbox;

  String? _cachedCurrentUserId;
  String? _cachedAuthUserId;

  String? get currentUserId => _cachedCurrentUserId;

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true; // 2. 标记已销毁
    super.dispose();
  }

  @override
  void notifyListeners() {
    // 3. 重写此方法：只有在未销毁时才通知 UI
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }
  
  Future<List<ChatThread>> loadInbox() async {
    _setLoading(true);
    try {
      final userId = await _requireUserId();
      return _chatsRepository.listForUser(userId);
    } finally {
      _setLoading(false);
    }
  }

  Stream<List<ChatMessage>> watchMessages(int chatId) {
    return _messagesRepository.watchForChat(chatId);
  }

  Stream<List<AiMessage>> watchAiMessages() {
    return _aiMessagesRepository.watchMessages();
  }

  Future<void> sendChatMessage({
    required int chatId,
    required String content,
  }) async {
    final senderId = await _requireUserId();
    final normalized = _requireNonEmptyContent(content);
    await _messagesRepository.send(
      chatId: chatId,
      senderId: senderId,
      content: normalized,
    );
  }

  Future<void> sendAiMessage(String text, {String? promptForAi}) {
    return _aiChatService.sendMessage(text, promptForAi: promptForAi);
  }

  Future<void> markChatAsRead(int chatId) async {
    final viewerId = await _requireUserId();
    await _messagesRepository.markAsRead(chatId: chatId, viewerId: viewerId);
  }

  Future<void> editChatMessage({
    required int messageId,
    required String content,
  }) async {
    final actorId = await _requireUserId();
    final normalized = _requireNonEmptyContent(content);
    await _messagesRepository.editMessage(
      messageId: messageId,
      actorId: actorId,
      content: normalized,
    );
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

  Future<void> deleteChatMessage(int messageId) async {
    final actorId = await _requireUserId();
    await _messagesRepository.deleteMessage(
      messageId: messageId,
      actorId: actorId,
    );
  }

  Future<void> deleteAiMessage(int messageId) {
    return _aiMessagesRepository.deleteMessage(messageId);
  }

  Future<void> pinChatMessage({
    required int chatId,
    required int messageId,
  }) async {
    final actorId = await _requireUserId();
    await _chatsRepository.pinMessage(
      chatId: chatId,
      messageId: messageId,
      actorId: actorId,
    );
  }

  Future<void> clearPinnedChatMessage({
    required int chatId,
    required int messageId,
  }) async {
    final actorId = await _requireUserId();
    await _chatsRepository.clearPinnedMessage(
      chatId: chatId,
      messageId: messageId,
      actorId: actorId,
    );
  }

  Future<List<ChatPinnedMessage>> listPinnedChatMessages(int chatId) async {
    final actorId = await _requireUserId();
    return _chatsRepository.listPinnedMessages(
      chatId: chatId,
      actorId: actorId,
    );
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
    final userId = _cachedCurrentUserId;
    if (userId == null) {
      throw StateError(
        'No active user profile. Load inbox after sign-in first.',
      );
    }

    return _chatsRepository.subscribeToChanges(
      userId: userId,
      onRelevantChange: onChange,
    );
  }

  Future<void> unsubscribeInboxChanges(RealtimeChannel channel) {
    return _chatsRepository.unsubscribe(channel);
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

    final user = await _usersRepository.getById(authUserId);
    _cachedAuthUserId = authUserId;
    _cachedCurrentUserId = user?.id;
    return _cachedCurrentUserId;
  }

  Future<String> _requireUserId() async {
    final userId = await refreshCurrentUserId();
    if (userId == null) {
      throw StateError(
        'No active user profile found. Sign in and create a users row first.',
      );
    }
    return userId;
  }

  String _requireNonEmptyContent(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'content', 'Message cannot be empty.');
    }
    return normalized;
  }

  void _setLoading(bool value) {
    if (_isLoadingInbox == value) {
      return;
    }
    _isLoadingInbox = value;
    notifyListeners();
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
