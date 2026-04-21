import '../models/chat_thread.dart';
import '../models/chat_pinned_message.dart';
import '../services/supabase_service.dart';
import '../core/utils/parsing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatsRepository {
  ChatsRepository();

  static const _table = 'chats';
  static const _withParticipantsSelect =
      'id,user1_id,user2_id,item_id,last_message,pinned_message_id,pinned_at,updated_at,'
      'user1:users!chats_user1_id_fkey(id,username,profile_image),'
      'user2:users!chats_user2_id_fkey(id,username,profile_image),'
      'item:items(owner_id,name,image_urls)';
    static const _withParticipantsSelectCompat =
      'id,user1_id,user2_id,item_id,last_message,pinned_message_id,pinned_at,updated_at,'
      'user1:users!chats_user1_id_fkey(id,username,profile_image),'
      'user2:users!chats_user2_id_fkey(id,username,profile_image),'
      'item:items(owner_id,title,image_url)';

  List<Map<String, dynamic>> _requireListOfMaps(
    dynamic response, {
    required String operation,
  }) {
    if (response is! List) {
      throw StateError('Unexpected $operation response: expected List.');
    }

    return response.map<Map<String, dynamic>>((row) {
      if (row is Map<String, dynamic>) {
        return row;
      }
      if (row is Map) {
        return row.map((key, value) => MapEntry(key.toString(), value));
      }
      throw StateError('Unexpected $operation row shape: expected Map.');
    }).toList();
  }

  Map<String, dynamic> _requireMap(
    dynamic response, {
    required String operation,
  }) {
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    throw StateError('Unexpected $operation response: expected Map.');
  }

  Future<List<ChatThread>> listForUser(String userId) async {
    dynamic response;
    try {
      response = await SupabaseService.client
          .from(_table)
          .select(_withParticipantsSelect)
          .or('user1_id.eq."$userId",user2_id.eq."$userId"')
          .order('updated_at', ascending: false);
    } on PostgrestException {
      response = await SupabaseService.client
          .from(_table)
          .select(_withParticipantsSelectCompat)
          .or('user1_id.eq."$userId",user2_id.eq."$userId"')
          .order('updated_at', ascending: false);
    }

    final rows = _requireListOfMaps(response, operation: 'listForUser');
    return rows.map<ChatThread>(ChatThread.fromMap).toList();
  }

  Future<ChatThread?> getById(int chatId) async {
    dynamic response;
    try {
      response = await SupabaseService.client
          .from(_table)
          .select(_withParticipantsSelect)
          .eq('id', chatId)
          .maybeSingle();
    } on PostgrestException {
      response = await SupabaseService.client
          .from(_table)
          .select(_withParticipantsSelectCompat)
          .eq('id', chatId)
          .maybeSingle();
    }

    if (response == null) {
      return null;
    }
    return ChatThread.fromMap(_requireMap(response, operation: 'getById'));
  }

  Future<void> upsert(ChatThread chat) async {
    await SupabaseService.client.from(_table).upsert(chat.toInsertMap());
  }

  Future<ChatThread> createOrGetItemChat({
    required String currentUserId,
    required String otherUserId,
    required int itemId,
  }) async {
    try {
      final response = await SupabaseService.client.rpc(
        'create_or_get_item_chat',
        params: {
          'p_user_a': currentUserId,
          'p_user_b': otherUserId,
          'p_item_id': itemId,
        },
      );

      return ChatThread.fromMap(
        _requireMap(response, operation: 'create_or_get_item_chat'),
      );
    } on PostgrestException catch (error) {
      // Older databases may not have the RPC yet; fallback to direct table flow.
      final shouldFallback =
          error.code == 'PGRST202' ||
          error.code == '22P02';
      if (!shouldFallback) {
        rethrow;
      }

      return _createOrGetItemChatFallback(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        itemId: itemId,
      );
    }
  }

  Future<ChatThread> _createOrGetItemChatFallback({
    required String currentUserId,
    required String otherUserId,
    required int itemId,
  }) async {
    final lowUserId = currentUserId.compareTo(otherUserId) <= 0
        ? currentUserId
        : otherUserId;
    final highUserId = currentUserId.compareTo(otherUserId) <= 0
        ? otherUserId
        : currentUserId;

    final existingResponse = await SupabaseService.client
        .from(_table)
        .select(_withParticipantsSelect)
        .eq('user1_id', lowUserId)
        .eq('user2_id', highUserId)
        .eq('item_id', itemId)
        .limit(1);

    final existingRows = _requireListOfMaps(
      existingResponse,
      operation: 'create_or_get_item_chat_fallback_lookup',
    );
    if (existingRows.isNotEmpty) {
      return ChatThread.fromMap(existingRows.first);
    }

    try {
      final insertedResponse = await SupabaseService.client
          .from(_table)
          .insert({'user1_id': lowUserId, 'user2_id': highUserId, 'item_id': itemId})
          .select(_withParticipantsSelect)
          .single();

      return ChatThread.fromMap(
        _requireMap(
          insertedResponse,
          operation: 'create_or_get_item_chat_fallback_insert',
        ),
      );
    } on PostgrestException catch (error) {
      // Handle race where another client created the row first.
      if (error.code != '23505') {
        rethrow;
      }

      dynamic retryResponse;
      try {
        retryResponse = await SupabaseService.client
            .from(_table)
            .select(_withParticipantsSelect)
            .eq('user1_id', lowUserId)
            .eq('user2_id', highUserId)
            .eq('item_id', itemId)
            .limit(1);
      } on PostgrestException {
        retryResponse = await SupabaseService.client
            .from(_table)
            .select(_withParticipantsSelectCompat)
            .eq('user1_id', lowUserId)
            .eq('user2_id', highUserId)
            .eq('item_id', itemId)
            .limit(1);
      }

      final retryRows = _requireListOfMaps(
        retryResponse,
        operation: 'create_or_get_item_chat_fallback_retry',
      );
      if (retryRows.isNotEmpty) {
        return ChatThread.fromMap(retryRows.first);
      }

      // Legacy schema may enforce one chat per user pair only (without item_id).
      dynamic pairOnlyResponse;
      try {
        pairOnlyResponse = await SupabaseService.client
            .from(_table)
            .select(_withParticipantsSelect)
            .eq('user1_id', lowUserId)
            .eq('user2_id', highUserId)
            .limit(1);
      } on PostgrestException {
        pairOnlyResponse = await SupabaseService.client
            .from(_table)
            .select(_withParticipantsSelectCompat)
            .eq('user1_id', lowUserId)
            .eq('user2_id', highUserId)
            .limit(1);
      }

      final pairOnlyRows = _requireListOfMaps(
        pairOnlyResponse,
        operation: 'create_or_get_item_chat_fallback_pair_only',
      );
      if (pairOnlyRows.isNotEmpty) {
        return ChatThread.fromMap(pairOnlyRows.first);
      }

      rethrow;
    }
  }

  RealtimeChannel subscribeToChanges({
    required String userId,
    required void Function() onRelevantChange,
  }) {
    final channel = SupabaseService.client.channel(
      'public:chats:$userId:${DateTime.now().millisecondsSinceEpoch}',
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: _table,
      callback: (payload) {
        final next = payload.newRecord;
        final previous = payload.oldRecord;

        bool matchesParticipant(Map<String, dynamic> record) {
          final user1Id = parseString(
            record['user1_id'],
            fieldName: 'chats.user1_id',
          );
          final user2Id = parseString(
            record['user2_id'],
            fieldName: 'chats.user2_id',
          );
          return user1Id == userId || user2Id == userId;
        }

        final hasNext = next.isNotEmpty;
        final hasPrevious = previous.isNotEmpty;

        if ((hasNext && matchesParticipant(next)) ||
            (hasPrevious && matchesParticipant(previous))) {
          onRelevantChange();
        }
      },
    );

    channel.subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await SupabaseService.client.removeChannel(channel);
  }

  Future<void> updateLastMessage({
    required int chatId,
    required String messagePreview,
  }) async {
    await SupabaseService.client
        .from(_table)
        .update({
          'last_message': messagePreview,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', chatId);
  }

  Future<void> pinMessage({
    required int chatId,
    required int messageId,
    required String actorId,
  }) async {
    await SupabaseService.client.rpc(
      'pin_message_as_user',
      params: {
        'p_chat_id': chatId,
        'p_message_id': messageId,
        'p_actor_id': actorId,
      },
    );
  }

  Future<void> clearPinnedMessage({
    required int chatId,
    required int messageId,
    required String actorId,
  }) async {
    await SupabaseService.client.rpc(
      'unpin_message_as_user',
      params: {
        'p_chat_id': chatId,
        'p_message_id': messageId,
        'p_actor_id': actorId,
      },
    );
  }

  Future<List<ChatPinnedMessage>> listPinnedMessages({
    required int chatId,
    required String actorId,
  }) async {
    final response = await SupabaseService.client.rpc(
      'list_pinned_messages_as_user',
      params: {'p_chat_id': chatId, 'p_actor_id': actorId},
    );

    final rows = _requireListOfMaps(
      response,
      operation: 'list_pinned_messages_as_user',
    );
    return rows.map<ChatPinnedMessage>(ChatPinnedMessage.fromMap).toList();
  }
}
