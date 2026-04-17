import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_message.dart';
import '../models/ai_pinned_message.dart';
import '../repositories/ai_messages_repository.dart';

class AiChatService {
  final AiMessagesRepository _repository;
  final SupabaseClient _supabase;

  AiChatService({AiMessagesRepository? repository, SupabaseClient? supabase})
    : _repository = repository ?? AiMessagesRepository(),
      _supabase = supabase ?? Supabase.instance.client;

  Stream<List<AiMessage>> watchAiMessages() {
    return _repository.watchMessages();
  }

  Future<List<AiMessage>> fetchAiMessages() {
    return _repository.fetchMessages();
  }

  Future<void> editMessage({
    required int messageId,
    required String content,
  }) {
    return _repository.editMessage(messageId: messageId, content: content);
  }

  Future<void> deleteMessage(int messageId) {
    return _repository.deleteMessage(messageId);
  }

  Future<void> pinMessage(int messageId) {
    return _repository.pinMessage(messageId);
  }

  Future<void> unpinMessage(int messageId) {
    return _repository.unpinMessage(messageId);
  }

  Future<List<AiPinnedMessage>> listPinnedMessages() {
    return _repository.listPinnedMessages();
  }

  Future<void> sendMessage(
    String text, {
    String? promptForAi,
  }) async {
    if (text.trim().isEmpty) return;

    final modelPrompt = (promptForAi ?? text).trim();

    // 1. Insert user message directly
    await _repository.insertMessage(text.trim());

    // 2. Invoke Edge Function to get AI response
    try {
      await _supabase.functions.invoke(
        'ai_chat',
        body: {'message': modelPrompt},
      );
    } catch (e) {
      debugPrint('Error invoking ai_chat function: $e');
      // If we wanted, we could insert a fallback message stating the AI failed here
      await _repository.insertMessage(
        "I'm sorry, I'm having trouble connecting to the network right now. Please try again later.",
        isAi: true,
      );
    }
  }
}
