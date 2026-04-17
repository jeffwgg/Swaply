import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_message.dart';
import '../models/ai_pinned_message.dart';

class AiMessagesRepository {
  final SupabaseClient _supabase;

  AiMessagesRepository({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  Stream<List<AiMessage>> watchMessages() {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    return _supabase
        .from('ai_messages')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: true)
        .map((data) => data.map((json) => AiMessage.fromMap(json)).toList());
  }

  Future<List<AiMessage>> fetchMessages() async {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    final data = await _supabase
        .from('ai_messages')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);

    return (data as List<dynamic>)
        .map((json) => AiMessage.fromMap(json as Map<String, dynamic>))
        .toList();
  }

  Future<AiMessage> insertMessage(String content, {bool isAi = false}) async {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    final data = await _supabase
        .from('ai_messages')
        .insert({'user_id': userId, 'content': content, 'is_ai': isAi})
        .select()
        .single();

    return AiMessage.fromMap(data);
  }

  Future<void> editMessage({
    required int messageId,
    required String content,
  }) async {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    await _supabase
        .from('ai_messages')
        .update({'content': content.trim()})
        .eq('id', messageId)
        .eq('user_id', userId)
        .eq('is_ai', false);
  }

  Future<void> deleteMessage(int messageId) async {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    await _supabase
        .from('ai_messages')
        .delete()
        .eq('id', messageId)
        .eq('user_id', userId)
        .eq('is_ai', false);
  }

  Future<void> pinMessage(int messageId) async {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    await _supabase.from('ai_message_pins').upsert({
      'user_id': userId,
      'message_id': messageId,
    }, onConflict: 'user_id,message_id');
  }

  Future<void> unpinMessage(int messageId) async {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    await _supabase
        .from('ai_message_pins')
        .delete()
        .eq('user_id', userId)
        .eq('message_id', messageId);
  }

  Future<List<AiPinnedMessage>> listPinnedMessages() async {
    // TESTING ONLY: Hardcoding user id to '86369cf5-f4a3-458e-bbe8-8c957854efec'
    final userId = '86369cf5-f4a3-458e-bbe8-8c957854efec';

    final data = await _supabase
        .from('ai_message_pins')
        .select('message_id, pinned_at')
        .eq('user_id', userId)
        .order('pinned_at', ascending: false);

    return (data as List<dynamic>)
        .map((json) => AiPinnedMessage.fromMap(json as Map<String, dynamic>))
        .toList();
  }
}
