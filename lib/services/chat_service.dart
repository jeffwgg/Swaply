import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/chat_pinned_message.dart';
import '../models/chat_thread.dart';
import '../services/notification_service.dart';
import '../repositories/chats_repository.dart';
import '../repositories/local/local_chats_repository.dart';
import '../repositories/local/local_messages_repository.dart';
import '../repositories/messages_repository.dart';
import '../repositories/users_repository.dart';
import '../services/supabase_service.dart';

class ChatService {
  ChatService({
    ChatsRepository? chatsRepository,
    MessagesRepository? messagesRepository,
    LocalChatsRepository? localChatsRepository,
    LocalMessagesRepository? localMessagesRepository,
    UsersRepository? usersRepository,
    String? Function()? authUserIdProvider,
    Future<String?> Function(String authUserId)? appUserIdResolver,
  }) : _chatsRepository = chatsRepository ?? ChatsRepository(),
       _messagesRepository = messagesRepository ?? MessagesRepository(),
       _localChatsRepository = localChatsRepository ?? LocalChatsRepository(),
       _localMessagesRepository =
           localMessagesRepository ?? LocalMessagesRepository(),
       _usersRepository = usersRepository ?? UsersRepository(),
       _authUserIdProvider = authUserIdProvider ?? _defaultAuthUserIdProvider,
       _appUserIdResolver = appUserIdResolver;

  final ChatsRepository _chatsRepository;
  final MessagesRepository _messagesRepository;
  final LocalChatsRepository _localChatsRepository;
  final LocalMessagesRepository _localMessagesRepository;
  final UsersRepository _usersRepository;
  final String? Function() _authUserIdProvider;
  final Future<String?> Function(String authUserId)? _appUserIdResolver;

  final Map<int, StreamSubscription<List<ChatMessage>>> _remoteMessageMirrors =
      {};
  final Map<int, Timer> _remoteMessagePollers = {};
  bool _isDisposed = false;

  String? _cachedCurrentUserId;
  String? _cachedAuthUserId;

  String? get currentUserId => _cachedCurrentUserId;

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

    final resolvedUserId = _appUserIdResolver != null
        ? await _appUserIdResolver(authUserId)
        : (await _usersRepository.getById(authUserId))?.id;
    _cachedAuthUserId = authUserId;
    _cachedCurrentUserId = resolvedUserId;
    return _cachedCurrentUserId;
  }

  Future<List<ChatThread>> loadInbox() async {
    final userId = await _requireUserId();
    final localThreads = await _localChatsRepository.listForUser(userId);
    final remoteFuture = _chatsRepository.listForUser(userId);

    if (localThreads.isNotEmpty) {
      try {
        final remoteThreads = await remoteFuture.timeout(
          const Duration(milliseconds: 350),
        );
        await _localChatsRepository.upsertMany(remoteThreads);
        return remoteThreads;
      } on TimeoutException {
        unawaited(_refreshInboxCache(remoteFuture));
        return localThreads;
      } catch (_) {
        return localThreads;
      }
    }

    try {
      final remoteThreads = await remoteFuture;
      await _localChatsRepository.upsertMany(remoteThreads);
      return remoteThreads;
    } catch (_) {
      return localThreads;
    }
  }

  Future<ChatThread> createOrGetItemChat({
    required String otherUserId,
    required int itemId,
  }) async {
    final userId = await _requireUserId();
    _requireNonEmptyId(otherUserId, fieldName: 'otherUserId');
    _requirePositiveId(itemId, fieldName: 'itemId');
    final thread = await _chatsRepository.createOrGetItemChat(
      currentUserId: userId,
      otherUserId: otherUserId,
      itemId: itemId,
    );
    await _localChatsRepository.upsertOne(thread);
    return thread;
  }

  Stream<List<ChatMessage>> watchMessages(int chatId) {
    if (_isDisposed) {
      return const Stream.empty();
    }
    _requirePositiveId(chatId, fieldName: 'chatId');
    _ensureRemoteMessageMirror(chatId);
    _ensureRemoteMessagePoller(chatId);
    unawaited(_primeMessages(chatId));
    unawaited(flushPendingQueue(chatId: chatId));
    return _localMessagesRepository.watchForChat(chatId);
  }

  Future<ChatMessage> sendMessage({
    required int chatId,
    required String content,
  }) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    final normalizedContent = _requireNonEmptyContent(content);
    final senderId = await _requireUserId();

    final pending = await _localMessagesRepository.insertPending(
      chatId: chatId,
      senderId: senderId,
      content: normalizedContent,
    );
    await _localChatsRepository.updateLastMessage(
      chatId: chatId,
      messagePreview: normalizedContent,
    );

    try {
      final remote = await _messagesRepository.send(
        chatId: chatId,
        senderId: senderId,
        content: normalizedContent,
      );
      await _localMessagesRepository.resolvePendingWithRemote(
        pending: pending,
        remote: remote,
      );
      unawaited(
        _notifyRecipientForMessage(
          chatId: chatId,
          senderId: senderId,
          content: normalizedContent,
        ),
      );
      return remote;
    } catch (error) {
      await _localMessagesRepository.markPendingFailed(
        pending: pending,
        error: error,
      );
      return ChatMessage(
        id: pending.tempMessageId,
        chatId: chatId,
        senderId: senderId,
        content: normalizedContent,
        createdAt: pending.createdAt,
      );
    }
  }

  Future<void> flushPendingQueue({required int chatId}) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    final pendingMessages = await _localMessagesRepository.listPendingByChat(
      chatId,
    );
    if (pendingMessages.isEmpty) {
      return;
    }

    for (final pending in pendingMessages) {
      try {
        final remote = await _messagesRepository.send(
          chatId: pending.chatId,
          senderId: pending.senderId,
          content: pending.content,
        );
        await _localMessagesRepository.resolvePendingWithRemote(
          pending: pending,
          remote: remote,
        );
      } catch (error) {
        await _localMessagesRepository.markPendingFailed(
          pending: pending,
          error: error,
        );
        break;
      }
    }
  }

  Future<void> markChatAsRead(int chatId) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    final viewerId = await _requireUserId();
    await _messagesRepository.markAsRead(chatId: chatId, viewerId: viewerId);
    await _localMessagesRepository.markChatReadLocally(
      chatId: chatId,
      viewerId: viewerId,
    );
  }

  Future<void> editMessage({
    required int messageId,
    required String content,
  }) async {
    _requirePositiveId(messageId, fieldName: 'messageId');
    final normalizedContent = _requireNonEmptyContent(content);
    final actorId = await _requireUserId();
    await _messagesRepository.editMessage(
      messageId: messageId,
      actorId: actorId,
      content: normalizedContent,
    );
    await _localMessagesRepository.markMessageEditedLocally(
      messageId: messageId,
      content: normalizedContent,
    );
  }

  Future<void> deleteMessage(int messageId) async {
    _requirePositiveId(messageId, fieldName: 'messageId');
    final actorId = await _requireUserId();
    await _messagesRepository.deleteMessage(
      messageId: messageId,
      actorId: actorId,
    );
    await _localMessagesRepository.markMessageDeletedLocally(
      messageId: messageId,
      actorId: actorId,
    );
  }

  Future<void> pinMessage({required int chatId, required int messageId}) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    _requirePositiveId(messageId, fieldName: 'messageId');
    final actorId = await _requireUserId();
    return _chatsRepository.pinMessage(
      chatId: chatId,
      messageId: messageId,
      actorId: actorId,
    );
  }

  Future<void> clearPinnedMessage({
    required int chatId,
    required int messageId,
  }) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    _requirePositiveId(messageId, fieldName: 'messageId');
    final actorId = await _requireUserId();
    return _chatsRepository.clearPinnedMessage(
      chatId: chatId,
      messageId: messageId,
      actorId: actorId,
    );
  }

  Future<List<ChatPinnedMessage>> listPinnedMessages(int chatId) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    final actorId = await _requireUserId();
    return _chatsRepository.listPinnedMessages(
      chatId: chatId,
      actorId: actorId,
    );
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
      onRelevantChange: () {
        unawaited(_refreshInboxFromRemoteNow(userId));
        onChange();
      },
    );
  }

  Future<void> unsubscribeInboxChanges(RealtimeChannel channel) {
    return _chatsRepository.unsubscribe(channel);
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

  void _ensureRemoteMessageMirror(int chatId) {
    if (_isDisposed) {
      return;
    }
    if (_remoteMessageMirrors.containsKey(chatId)) {
      return;
    }

    _remoteMessageMirrors[chatId] = _messagesRepository
        .watchForChat(chatId)
        .listen((remoteMessages) async {
          if (_isDisposed) {
            return;
          }
          await _localMessagesRepository.upsertRemoteMessages(remoteMessages);
        }, onError: (_, __) {
          _restartRemoteMessageMirror(chatId);
        }, onDone: () {
          _restartRemoteMessageMirror(chatId);
        });
  }

  void _restartRemoteMessageMirror(int chatId) {
    final existing = _remoteMessageMirrors.remove(chatId);
    if (existing != null) {
      unawaited(existing.cancel());
    }
    if (_isDisposed) {
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (_isDisposed) {
        return;
      }
      _ensureRemoteMessageMirror(chatId);
    });
  }

  Future<void> _primeMessages(int chatId) async {
    try {
      final remoteMessages = await _messagesRepository.listForChat(chatId);
      await _localMessagesRepository.upsertRemoteMessages(remoteMessages);
    } catch (_) {}
  }

  void _ensureRemoteMessagePoller(int chatId) {
    if (_isDisposed || _remoteMessagePollers.containsKey(chatId)) {
      return;
    }

    _remoteMessagePollers[chatId] = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (_isDisposed) {
          return;
        }
        unawaited(_primeMessages(chatId));
      },
    );
  }

  Future<void> _refreshInboxCache(Future<List<ChatThread>> remoteFuture) async {
    try {
      final remoteThreads = await remoteFuture;
      await _localChatsRepository.upsertMany(remoteThreads);
    } catch (_) {}
  }

  Future<void> _refreshInboxFromRemoteNow(String userId) async {
    if (_isDisposed) {
      return;
    }
    try {
      final remoteThreads = await _chatsRepository.listForUser(userId);
      await _localChatsRepository.upsertMany(remoteThreads);
    } catch (_) {}
  }

  Future<void> _notifyRecipientForMessage({
    required int chatId,
    required String senderId,
    required String content,
  }) async {
    // Local notifications are now handled purely by Supabase realtime
    // listening to the 'messages' table directly, avoiding inserts
    // into the system 'notifications' table.
    return;
  }

  String _buildNotificationPreview(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('[[media]]')) {
      final lower = trimmed.toLowerCase();
      if (lower.contains('"type":"image"')) {
        return 'Photo';
      }
      if (lower.contains('"type":"voice"')) {
        return 'Voice message';
      }
      if (lower.contains('"type":"document"')) {
        return 'Document';
      }
      return 'Attachment';
    }

    if (trimmed.startsWith('[Location]')) {
      return 'Location shared';
    }

    return trimmed;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    final subscriptions = _remoteMessageMirrors.values.toList(growable: false);
    _remoteMessageMirrors.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    final pollers = _remoteMessagePollers.values.toList(growable: false);
    _remoteMessagePollers.clear();
    for (final poller in pollers) {
      poller.cancel();
    }
  }

  void _requireNonEmptyId(String value, {required String fieldName}) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, fieldName, 'Must be a non-empty UUID.');
    }
  }

  void _requirePositiveId(int value, {required String fieldName}) {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        fieldName,
        'Must be a positive integer.',
      );
    }
  }

  String _requireNonEmptyContent(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'content', 'Message cannot be empty.');
    }
    return normalized;
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
