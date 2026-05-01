import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/app_user.dart';
import '../repositories/users_repository.dart';

class ProfileService {
  static final _repo = UsersRepository();
  static const String _storageBucket = 'profile';
  static final ImagePicker _imagePicker = ImagePicker();

  static Future<File?> pickImageFromCamera() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      return pickedFile != null ? File(pickedFile.path) : null;
    } catch (e) {
      print('Error picking image from camera: $e');
      return null;
    }
  }

  static Future<File?> pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      return pickedFile != null ? File(pickedFile.path) : null;
    } catch (e) {
      print('Error picking image from gallery: $e');
      return null;
    }
  }

  static Future<String?> uploadProfilePicture(
    File imageFile,
    String userId,
  ) async {
    try {
      final filePath = '$userId/profile.jpg';
      final fileBytes = await imageFile.readAsBytes();

      await SupabaseService.client.storage
          .from(_storageBucket)
          .uploadBinary(
            filePath,
            fileBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      final publicUrl = SupabaseService.client.storage
          .from(_storageBucket)
          .getPublicUrl(filePath);

      await SupabaseService.client
          .from('users')
          .update({'profile_image': publicUrl})
          .eq('id', userId);

      return publicUrl;
    } catch (e) {
      print('Error uploading profile picture: $e');
      return null;
    }
  }

  /// Delete old avatar if exists
  static Future<void> deleteOldAvatar(String userId) async {
    try {
      final filePath = '$userId/profile.jpg';
      await SupabaseService.client.storage.from(_storageBucket).remove([
        filePath,
      ]);
    } catch (e) {
      print('Note: Could not delete old avatar: $e');
    }
  }

  static Future<AppUser?> getProfile(String userId) {
    return UsersRepository().getById(userId);
  }

  //validation
  static bool isValidPhoneNumber(String phone) {
    phone = phone.replaceAll(RegExp(r'\s'), '');

    if (!RegExp(r'^\d+$').hasMatch(phone)) {
      return false;
    }

    return phone.length >= 10 && phone.length <= 12;
  }

  /// Validate full name - must contain only alphabetic characters and spaces
  static bool isValidFullName(String fullName) {
    fullName = fullName.trim();
    // Only allow letters (a-z, A-Z) and spaces
    return RegExp(r'^[a-zA-Z\s]+$').hasMatch(fullName);
  }

  /// Validate username - max 10 characters
  static bool isValidUsername(String username) {
    if (username.isEmpty) return false;
    if (username.length < 3) return false;
    if (username.length > 10) return false;
    // Allow letters, numbers, and underscores
    return RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username);
  }

  // ✅ Check duplicate phone
  static Future<bool> isPhoneDuplicate(String phone, String userId) async {
    try {
      final response = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('phone', phone)
          .neq('id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      print("Error checking phone duplicate: $e");
      return false;
    }
  }

  static Future<String?> updateProfile({
    required String userId,
    required Map<String, dynamic> updates,
    required String? originalUsername,
    required String currentUsername,
    required bool isUsernameLocked,
  }) async {
    try {
      final repo = UsersRepository();

      // 🔍 username duplicate
      if (originalUsername != null && currentUsername != originalUsername) {
        final taken = await repo.isUsernameTaken(currentUsername, userId);
        if (taken) return "USERNAME_TAKEN";
      }

      // 🔄 username flag
      if (originalUsername != null &&
          currentUsername != originalUsername &&
          !isUsernameLocked) {
        await repo.updateUsernameFlag();
      }

      // 💾 update user
      await repo.updateUser(userId, updates);

      return null;
    } catch (e) {
      print("Service error: $e");
      return e.toString();
    }
  }

  static Future<String?> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _repo.changePassword(
        email: email,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> createProfile({
    required String userId,
    required String email,
    required String username,
    required String fullName,
    required String bio,
    required String phone,
    required String gender,
    required DateTime? birthdate,
  }) async {
    // 🔍 validation
    if (fullName.isEmpty) return "Full name required";
    if (username.length < 3) return "Username too short";
    if (!isValidPhoneNumber(phone)) return "Invalid phone";

    if (birthdate == null) {
      return "Please select birthdate";
    }

    final age = DateTime.now().year - birthdate.year;
    if (age < 13) return "Must be 13+";

    // 🔍 duplicate
    final phoneTaken = await _repo.isPhoneTakenForCreate(phone);
    if (phoneTaken) return "PHONE_TAKEN";

    try {
      await _repo.insertUser({
        'id': userId,
        'email': email,
        'username': username,
        'full_name': fullName,
        'bio': bio,
        'phone': phone,
        'gender': gender,
        'birthdate': birthdate.toIso8601String().split('T')[0],
        'created_at': DateTime.now().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      print("Create profile database error: ${e.message}");
      return e.message;
    } catch (e) {
      print("Create profile error: $e");
      return e.toString();
    }

    return null;
  }

  static Stream<AppUser?> watchProfile(String userId) {
    return SupabaseService.client
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) {
          if (data.isEmpty) return null;
          return AppUser.fromMap(data.first);
        });
  }
}
