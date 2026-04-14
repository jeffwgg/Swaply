import '../models/chat_message.dart';
import '../services/supabase_service.dart';

class MessagesRepository {
  MessagesRepository();

  static const _table = 'messages';

  Future<List<ChatMessage>> listForChat(int chatId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('chat_id', chatId)
        .order('created_at', ascending: true);

    return response.map<ChatMessage>(ChatMessage.fromMap).toList();
  }

  Stream<List<ChatMessage>> watchForChat(int chatId) {
    return SupabaseService.client
        .from(_table)
        .stream(primaryKey: const ['id'])
        .eq('chat_id', chatId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map(ChatMessage.fromMap).toList());
  }

  Future<ChatMessage> send({
    required int chatId,
    required int senderId,
    required String content,
  }) async {
    final response = await SupabaseService.client
        .from(_table)
        .insert({
          'chat_id': chatId,
          'sender_id': senderId,
          'content': content.trim(),
        })
        .select()
        .single();

    return ChatMessage.fromMap(response);
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
