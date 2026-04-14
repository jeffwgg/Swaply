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
    return AppUser(
      id: parseInt(map['id'], fieldName: 'users.id'),
      authUserId: parseString(
        map['auth_user_id'],
        fieldName: 'users.auth_user_id',
      ),
      username: parseString(map['username'], fieldName: 'users.username'),
      email: parseString(map['email'], fieldName: 'users.email'),
      profileImage: parseNullableString(
        map['profile_image'],
        fieldName: 'users.profile_image',
      ),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'users.created_at',
      ),
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
