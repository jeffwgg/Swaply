import '../core/utils/parsing.dart';

class AppUser {
  final int id;
  final String authUserId;
  final String username;
  final String email;
  final String? profileImage;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.authUserId,
    required this.username,
    required this.email,
    this.profileImage,
    required this.createdAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    DateTime parseDateTime(dynamic value) {
      if (value is DateTime) {
        return value;
      }
      return DateTime.parse(value as String);
    }

    return AppUser(
      id: parseInt(map['id'], fieldName: 'users.id'),
      authUserId: map['auth_user_id'] as String,
      username: map['username'] as String,
      email: map['email'] as String,
      profileImage: map['profile_image'] as String?,
      createdAt: parseDateTime(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'auth_user_id': authUserId,
      'username': username,
      'email': email,
      'profile_image': profileImage,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
