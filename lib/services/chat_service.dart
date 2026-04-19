import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/chat_pinned_message.dart';
import '../models/chat_thread.dart';
import '../repositories/chats_repository.dart';
import '../repositories/messages_repository.dart';
import '../repositories/users_repository.dart';
import '../services/supabase_service.dart';

class ChatService {
  ChatService({
    ChatsRepository? chatsRepository,
    MessagesRepository? messagesRepository,
    UsersRepository? usersRepository,
    String? Function()? authUserIdProvider,
    Future<String?> Function(String authUserId)? appUserIdResolver,
  }) : _chatsRepository = chatsRepository ?? ChatsRepository(),
       _messagesRepository = messagesRepository ?? MessagesRepository(),
       _usersRepository = usersRepository ?? UsersRepository(),
       _authUserIdProvider = authUserIdProvider ?? _defaultAuthUserIdProvider,
       _appUserIdResolver = appUserIdResolver;

  final ChatsRepository _chatsRepository;
  final MessagesRepository _messagesRepository;
  final UsersRepository _usersRepository;
  final String? Function() _authUserIdProvider;
  final Future<String?> Function(String authUserId)? _appUserIdResolver;

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
    return _chatsRepository.listForUser(userId);
  }

  Future<ChatThread> createOrGetItemChat({
    required String otherUserId,
    required int itemId,
  }) async {
    final userId = await _requireUserId();
    _requireNonEmptyId(otherUserId, fieldName: 'otherUserId');
    _requirePositiveId(itemId, fieldName: 'itemId');
    return _chatsRepository.createOrGetItemChat(
      currentUserId: userId,
      otherUserId: otherUserId,
      itemId: itemId,
    );
  }

  Stream<List<ChatMessage>> watchMessages(int chatId) {
    return _messagesRepository.watchForChat(chatId);
  }

  Future<ChatMessage> sendMessage({
    required int chatId,
    required String content,
  }) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    final normalizedContent = _requireNonEmptyContent(content);
    final senderId = await _requireUserId();
    return _messagesRepository.send(
      chatId: chatId,
      senderId: senderId,
      content: normalizedContent,
    );
  }

  Future<void> markChatAsRead(int chatId) async {
    _requirePositiveId(chatId, fieldName: 'chatId');
    final viewerId = await _requireUserId();
    return _messagesRepository.markAsRead(chatId: chatId, viewerId: viewerId);
  }

  Future<void> editMessage({
    required int messageId,
    required String content,
  }) async {
    _requirePositiveId(messageId, fieldName: 'messageId');
    final normalizedContent = _requireNonEmptyContent(content);
    final actorId = await _requireUserId();
    return _messagesRepository.editMessage(
      messageId: messageId,
      actorId: actorId,
      content: normalizedContent,
    );
  }

  Future<void> deleteMessage(int messageId) async {
    _requirePositiveId(messageId, fieldName: 'messageId');
    final actorId = await _requireUserId();
    return _messagesRepository.deleteMessage(
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
      onRelevantChange: onChange,
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
