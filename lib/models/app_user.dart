import '../core/utils/parsing.dart';

class AppUser {
  final String id;
  final String username;
  final String email;
  final String? profileImage;
  final DateTime createdAt;

  final String? fullName;
  final String? bio;
  final String? phone;
  final String? gender;
  final DateTime? birthdate;
  final double? rating;
  final int? totalReviews;
  final DateTime? updatedAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.profileImage,
    required this.createdAt,

    this.fullName,
    this.bio,
    this.phone,
    this.gender,
    this.birthdate,
    this.rating,
    this.totalReviews,
    this.updatedAt,
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

      fullName: parseNullableString(map['full_name'], fieldName: 'users.full_name'),
      bio: parseNullableString(map['bio'], fieldName: 'users.bio'),
      phone: parseNullableString(map['phone'], fieldName: 'users.phone'),
      gender: parseNullableString(map['gender'], fieldName: 'users.gender'),
      birthdate: parseNullableDateTime(map['birthdate'], fieldName: 'users.birthdate'),
      rating: map['rating'] != null ? (map['rating'] as num).toDouble() : null,
      totalReviews: map['total_reviews'] != null ? map['total_reviews'] as int : null,
      updatedAt: parseNullableDateTime(map['updated_at'], fieldName: 'users.updated_at'),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'profile_image': profileImage,
      'full_name': fullName,
      'bio': bio,
      'phone': phone,
      'gender': gender,
      'birthdate': birthdate?.toIso8601String(),
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

      'full_name': fullName,
      'bio': bio,
      'phone': phone,
      'gender': gender,
      'birthdate': birthdate?.toIso8601String(),
      'rating': rating,
      'total_reviews': totalReviews,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}