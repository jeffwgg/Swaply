class ChatThread {
  final String id;
  final String user1Id;
  final String user2Id;
  final String? itemId;
  final String? lastMessage;
  final DateTime updatedAt;

  const ChatThread({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    this.itemId,
    this.lastMessage,
    required this.updatedAt,
  });

  factory ChatThread.fromMap(Map<String, dynamic> map) {
    return ChatThread(
      id: map['id'] as String,
      user1Id: map['user1_id'] as String,
      user2Id: map['user2_id'] as String,
      itemId: map['item_id'] as String?,
      lastMessage: map['last_message'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user1_id': user1Id,
      'user2_id': user2Id,
      'item_id': itemId,
      'last_message': lastMessage,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
