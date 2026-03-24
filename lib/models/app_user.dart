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
      id: map['id'] as String,
      username: map['username'] as String,
      email: map['email'] as String,
      profileImage: map['profile_image'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

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
