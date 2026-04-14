import '../core/utils/parsing.dart';

class ChatPinnedMessage {
  final int chatId;
  final int messageId;
  final DateTime pinnedAt;

  const ChatPinnedMessage({
    required this.chatId,
    required this.messageId,
    required this.pinnedAt,
  });

  factory ChatPinnedMessage.fromMap(Map<String, dynamic> map) {
    return ChatPinnedMessage(
      chatId: parseInt(
        map['chat_id'],
        fieldName: 'chat_pinned_messages.chat_id',
      ),
      messageId: parseInt(
        map['message_id'],
        fieldName: 'chat_pinned_messages.message_id',
      ),
      pinnedAt: parseDateTime(
        map['pinned_at'],
        fieldName: 'chat_pinned_messages.pinned_at',
      ),
    );
  }
}
