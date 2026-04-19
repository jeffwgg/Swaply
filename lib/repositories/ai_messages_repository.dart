import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_message.dart';
import '../models/ai_pinned_message.dart';

class AiMessagesRepository {
  static const String _defaultWelcomeMessage =
      'Hi! I\'m Swaply Buddy. I can help you with listings, trades, requests, and chat tips anytime.';

  final SupabaseClient _supabase;

  AiMessagesRepository({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  String _requireAuthUserId() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw StateError('No authenticated user found for AI chat operations.');
    }
    return userId;
  }

  Stream<List<AiMessage>> watchMessages() {
    final userId = _requireAuthUserId();

    return _supabase
        .from('ai_messages')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: true)
        .map((data) => data.map((json) => AiMessage.fromMap(json)).toList());
  }

  Future<List<AiMessage>> fetchMessages() async {
    final userId = _requireAuthUserId();

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
    final userId = _requireAuthUserId();

    final data = await _supabase
        .from('ai_messages')
        .insert({'user_id': userId, 'content': content, 'is_ai': isAi})
        .select()
        .single();

    return AiMessage.fromMap(data);
  }

  Future<void> ensureConversationInitialized({String? welcomeMessage}) async {
    final userId = _requireAuthUserId();

    final existing = await _supabase
        .from('ai_messages')
        .select('id')
        .eq('user_id', userId)
        .order('created_at', ascending: true)
        .limit(1);

    if ((existing as List<dynamic>).isNotEmpty) {
      return;
    }

    final inserted = await _supabase
        .from('ai_messages')
        .insert({
          'user_id': userId,
          'content': (welcomeMessage ?? _defaultWelcomeMessage).trim(),
          'is_ai': true,
        })
        .select('id')
        .single();

    final messageId = inserted['id'] as int;

    await _supabase.from('ai_message_pins').upsert({
      'user_id': userId,
      'message_id': messageId,
    }, onConflict: 'user_id,message_id');
  }

  Future<void> editMessage({
    required int messageId,
    required String content,
  }) async {
    final userId = _requireAuthUserId();

    await _supabase
        .from('ai_messages')
        .update({'content': content.trim()})
        .eq('id', messageId)
        .eq('user_id', userId)
        .eq('is_ai', false);
  }

  Future<void> deleteMessage(int messageId) async {
    final userId = _requireAuthUserId();

    await _supabase
        .from('ai_messages')
        .delete()
        .eq('id', messageId)
        .eq('user_id', userId)
        .eq('is_ai', false);
  }

  Future<void> pinMessage(int messageId) async {
    final userId = _requireAuthUserId();

    await _supabase.from('ai_message_pins').upsert({
      'user_id': userId,
      'message_id': messageId,
    }, onConflict: 'user_id,message_id');
  }

  Future<void> unpinMessage(int messageId) async {
    final userId = _requireAuthUserId();

    await _supabase
        .from('ai_message_pins')
        .delete()
        .eq('user_id', userId)
        .eq('message_id', messageId);
  }

  Future<List<AiPinnedMessage>> listPinnedMessages() async {
    final userId = _requireAuthUserId();

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
