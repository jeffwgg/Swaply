import '../core/utils/parsing.dart';

class AiPinnedMessage {
  final int messageId;
  final DateTime pinnedAt;

  const AiPinnedMessage({
    required this.messageId,
    required this.pinnedAt,
  });

  factory AiPinnedMessage.fromMap(Map<String, dynamic> map) {
    return AiPinnedMessage(
      messageId: parseInt(
        map['message_id'],
        fieldName: 'ai_message_pins.message_id',
      ),
      pinnedAt: parseDateTime(
        map['pinned_at'],
        fieldName: 'ai_message_pins.pinned_at',
      ),
    );
  }
}
