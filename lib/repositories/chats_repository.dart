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
      'item:items(owner_id,name)';

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
    final response = await SupabaseService.client
        .from(_table)
        .select(_withParticipantsSelect)
      .or('user1_id.eq."$userId",user2_id.eq."$userId"')
        .order('updated_at', ascending: false);

    final rows = _requireListOfMaps(response, operation: 'listForUser');
    return rows.map<ChatThread>(ChatThread.fromMap).toList();
  }

  Future<ChatThread?> getById(int chatId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select(_withParticipantsSelect)
        .eq('id', chatId)
        .maybeSingle();

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
