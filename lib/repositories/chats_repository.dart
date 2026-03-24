import '../models/chat_thread.dart';
import '../services/supabase_service.dart';

class ChatsRepository {
  ChatsRepository();

  static const _table = 'chats';

  Future<List<ChatThread>> listForUser(String userId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .or('user1_id.eq.$userId,user2_id.eq.$userId')
        .order('updated_at', ascending: false);

    return response.map<ChatThread>(ChatThread.fromMap).toList();
  }

  Future<ChatThread?> getById(String chatId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', chatId)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return ChatThread.fromMap(response);
  }

  Future<void> upsert(ChatThread chat) async {
    await SupabaseService.client.from(_table).upsert(chat.toMap());
  }

  Future<void> updateLastMessage({
    required String chatId,
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
}
