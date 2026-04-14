import '../core/utils/parsing.dart';

class ChatThread {
  final int id;
  final int user1Id;
  final int user2Id;
  final String? user1Name;
  final String? user2Name;
  final String? user1ProfileImage;
  final String? user2ProfileImage;
  final int? itemId;
  final String? itemTitle;
  final int? itemOwnerId;
  final String? lastMessage;
  final int? pinnedMessageId;
  final DateTime? pinnedAt;
  final DateTime updatedAt;

  const ChatThread({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    this.user1Name,
    this.user2Name,
    this.user1ProfileImage,
    this.user2ProfileImage,
    this.itemId,
    this.itemTitle,
    this.itemOwnerId,
    this.lastMessage,
    this.pinnedMessageId,
    this.pinnedAt,
    required this.updatedAt,
  });

  factory ChatThread.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? parseNestedMap(dynamic value) {
      if (value == null) {
        return null;
      }
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return value.map((key, nestedValue) {
          return MapEntry(key.toString(), nestedValue);
        });
      }
      return null;
    }

    final user1 = parseNestedMap(map['user1']);
    final user2 = parseNestedMap(map['user2']);
    final item = parseNestedMap(map['item']);

    return ChatThread(
      id: parseInt(map['id'], fieldName: 'chats.id'),
      user1Id: parseInt(map['user1_id'], fieldName: 'chats.user1_id'),
      user2Id: parseInt(map['user2_id'], fieldName: 'chats.user2_id'),
      user1Name: user1 == null
          ? null
          : parseNullableString(user1['username'], fieldName: 'users.username'),
      user2Name: user2 == null
          ? null
          : parseNullableString(user2['username'], fieldName: 'users.username'),
      user1ProfileImage: user1 == null
          ? null
          : parseNullableString(
              user1['profile_image'],
              fieldName: 'users.profile_image',
            ),
      user2ProfileImage: user2 == null
          ? null
          : parseNullableString(
              user2['profile_image'],
              fieldName: 'users.profile_image',
            ),
      itemId: parseNullableInt(map['item_id'], fieldName: 'chats.item_id'),
      itemTitle: item == null
          ? null
          : parseNullableString(item['title'], fieldName: 'items.title'),
      itemOwnerId: item == null
          ? null
          : parseNullableInt(item['owner_id'], fieldName: 'items.owner_id'),
      lastMessage: parseNullableString(
        map['last_message'],
        fieldName: 'chats.last_message',
      ),
      pinnedMessageId: parseNullableInt(
        map['pinned_message_id'],
        fieldName: 'chats.pinned_message_id',
      ),
      pinnedAt: parseNullableDateTime(
        map['pinned_at'],
        fieldName: 'chats.pinned_at',
      ),
      updatedAt: parseDateTime(
        map['updated_at'],
        fieldName: 'chats.updated_at',
      ),
    );
  }

  int otherUserId(int currentUserId) {
    return currentUserId == user1Id ? user2Id : user1Id;
  }

  String otherUserName(int currentUserId) {
    final fallbackId = otherUserId(currentUserId);
    final fallbackText = fallbackId.toString();
    final fallbackPreview = fallbackText.length <= 8
        ? fallbackText
        : fallbackText.substring(0, 8);
    if (currentUserId == user1Id) {
      return user2Name ?? fallbackPreview;
    }
    return user1Name ?? fallbackPreview;
  }

  String? otherUserProfileImage(int currentUserId) {
    return currentUserId == user1Id ? user2ProfileImage : user1ProfileImage;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user1_id': user1Id,
      'user2_id': user2Id,
      'item_id': itemId,
      'last_message': lastMessage,
      'pinned_message_id': pinnedMessageId,
      'pinned_at': pinnedAt?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
