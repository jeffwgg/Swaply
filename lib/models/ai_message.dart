import '../core/utils/parsing.dart';

class AiMessage {
  final int id;
  final String userId;
  final String content;
  final bool isAi;
  final DateTime createdAt;

  const AiMessage({
    required this.id,
    required this.userId,
    required this.content,
    this.isAi = false,
    required this.createdAt,
  });

  factory AiMessage.fromMap(Map<String, dynamic> map) {
    return AiMessage(
      id: parseInt(map['id'], fieldName: 'ai_messages.id'),
      userId: parseString(map['user_id'], fieldName: 'ai_messages.user_id'),
      content: parseString(map['content'], fieldName: 'ai_messages.content'),
      isAi: map['is_ai'] as bool? ?? false,
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'ai_messages.created_at',
      ).toLocal(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'content': content,
      'is_ai': isAi,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  AiMessage copyWith({
    int? id,
    String? userId,
    String? content,
    bool? isAi,
    DateTime? createdAt,
  }) {
    return AiMessage(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      isAi: isAi ?? this.isAi,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
