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
    required int senderId,
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

  Future<void> markAsRead({required int chatId, required int viewerId}) async {
    await SupabaseService.client.rpc(
      'mark_chat_as_read_as_user',
      params: {'p_chat_id': chatId, 'p_actor_id': viewerId},
    );
  }

  Future<void> editMessage({
    required int messageId,
    required int actorId,
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
    required int actorId,
  }) async {
    await SupabaseService.client.rpc(
      'delete_message_as_user',
      params: {'p_message_id': messageId, 'p_actor_id': actorId},
    );
  }
}
