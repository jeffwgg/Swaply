import '../models/chat_message.dart';
import '../services/supabase_service.dart';

class MessagesRepository {
  MessagesRepository();

  static const _table = 'messages';

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

  Future<List<ChatMessage>> listForChat(int chatId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('chat_id', chatId)
        .order('created_at', ascending: true);

    final rows = _requireListOfMaps(response, operation: 'listForChat');
    return rows.map<ChatMessage>(ChatMessage.fromMap).toList();
  }

  Stream<List<ChatMessage>> watchForChat(int chatId) {
    return SupabaseService.client
        .from(_table)
        .stream(primaryKey: const ['id'])
        .eq('chat_id', chatId)
        .order('created_at', ascending: true)
        .map((rows) {
          final list = _requireListOfMaps(rows, operation: 'watchForChat');
          return list.map(ChatMessage.fromMap).toList();
        });
  }

  Future<ChatMessage> send({
    required int chatId,
    required String senderId,
    required String content,
  }) async {
    final response = await SupabaseService.client
        .from(_table)
        .insert(
          ChatMessage.createInsertMap(
            chatId: chatId,
            senderId: senderId,
            content: content.trim(),
          ),
        )
        .select()
        .single();

    return ChatMessage.fromMap(_requireMap(response, operation: 'send'));
  }

  Future<void> markAsRead({required int chatId, required String viewerId}) async {
    try {
      // Try the RPC first (exists when migrations have been applied).
      await SupabaseService.client.rpc(
        'mark_chat_as_read_as_user',
        params: {'p_chat_id': chatId, 'p_actor_id': viewerId},
      );
    } catch (_) {
      // Fallback: direct update for the legacy `is_read boolean` schema
      // (initial schema before the read_at migration was applied).
      await SupabaseService.client
          .from(_table)
          .update({'is_read': true})
          .eq('chat_id', chatId)
          .neq('sender_id', viewerId)
          .eq('is_read', false);
    }
  }

  Future<void> editMessage({
    required int messageId,
    required String actorId,
    required String content,
  }) async {
    await SupabaseService.client.rpc(
      'edit_message_as_user',
      params: {
        'p_message_id': messageId,
        'p_actor_id': actorId,
        'p_content': content.trim(),
      },
    );
  }

  Future<void> deleteMessage({
    required int messageId,
    required String actorId,
  }) async {
    await SupabaseService.client.rpc(
      'delete_message_as_user',
      params: {'p_message_id': messageId, 'p_actor_id': actorId},
    );
  }
}
