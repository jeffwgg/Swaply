import '../core/utils/parsing.dart';

class ChatMessage {
  final int id;
  final int chatId;
  final int senderId;
  final String content;
  final DateTime? readAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final int? deletedBy;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.readAt,
    this.editedAt,
    this.deletedAt,
    this.deletedBy,
    required this.createdAt,
  });

  bool get isRead => readAt != null;
  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: parseInt(map['id'], fieldName: 'messages.id'),
      chatId: parseInt(map['chat_id'], fieldName: 'messages.chat_id'),
      senderId: parseInt(map['sender_id'], fieldName: 'messages.sender_id'),
      content: parseString(map['content'], fieldName: 'messages.content'),
      readAt: parseNullableDateTime(
        map['read_at'],
        fieldName: 'messages.read_at',
      ),
      editedAt: parseNullableDateTime(
        map['edited_at'],
        fieldName: 'messages.edited_at',
      ),
      deletedAt: parseNullableDateTime(
        map['deleted_at'],
        fieldName: 'messages.deleted_at',
      ),
      deletedBy: parseNullableInt(
        map['deleted_by'],
        fieldName: 'messages.deleted_by',
      ),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'messages.created_at',
      ),
    );
  }

  static Map<String, dynamic> createInsertMap({
    required int chatId,
    required int senderId,
    required String content,
  }) {
    return {'chat_id': chatId, 'sender_id': senderId, 'content': content};
  }

  Map<String, dynamic> toInsertMap() {
    return {'chat_id': chatId, 'sender_id': senderId, 'content': content};
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'content': content,
      'read_at': readAt?.toIso8601String(),
      'edited_at': editedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'deleted_by': deletedBy,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
