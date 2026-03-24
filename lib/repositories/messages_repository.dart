import '../models/chat_message.dart';
import '../services/supabase_service.dart';

class MessagesRepository {
  MessagesRepository();

  static const _table = 'messages';

  Future<List<ChatMessage>> listForChat(String chatId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('chat_id', chatId)
        .order('created_at', ascending: true);

    return response.map<ChatMessage>(ChatMessage.fromMap).toList();
  }

  Future<void> send(ChatMessage message) async {
    await SupabaseService.client.from(_table).insert(message.toMap());
  }

  Future<void> markAsRead({
    required String chatId,
    required String viewerId,
  }) async {
    await SupabaseService.client
        .from(_table)
        .update({'is_read': true})
        .eq('chat_id', chatId)
        .neq('sender_id', viewerId)
        .eq('is_read', false);
  }
}
