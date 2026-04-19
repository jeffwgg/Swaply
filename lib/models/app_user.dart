import '../core/utils/parsing.dart';

class AppUser {
  final String id;
  final String username;
  final String email;
  final String? profileImage;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.profileImage,
    required this.createdAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: parseString(map['id'], fieldName: 'users.id'),
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

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'profile_image': profileImage,
    };
  }

  Map<String, dynamic> toUpsertMap() => toInsertMap();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'profile_image': profileImage,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
