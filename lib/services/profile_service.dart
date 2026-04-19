import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/app_user.dart';
import '../repositories/users_repository.dart';

class ProfileService {
  static const String _storageBucket = 'avatars';
  static final ImagePicker _imagePicker = ImagePicker();

  /// Pick an image from camera
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

  /// Pick an image from gallery
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

  /// Upload image to Supabase Storage and update user profile
  static Future<String?> uploadProfilePicture(File imageFile, String userId) async {
    try {
      final fileName = 'avatar_$userId.jpg';
      final fileBytes = await imageFile.readAsBytes();

      // Upload to storage
      await SupabaseService.client.storage
          .from(_storageBucket)
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      // Get public URL
      final publicUrl = SupabaseService.client.storage
          .from(_storageBucket)
          .getPublicUrl(fileName);

      // Update user profile in database
      await SupabaseService.client
          .from('users')
          .update({'avatar_url': publicUrl})
          .eq('auth_user_id', userId);

      return publicUrl;
    } catch (e) {
      print('Error uploading profile picture: $e');
      return null;
    }
  }

  /// Delete old avatar if exists
  static Future<void> deleteOldAvatar(String userId) async {
    try {
      final fileName = 'avatar_$userId.jpg';
      await SupabaseService.client.storage.from(_storageBucket).remove([fileName]);
    } catch (e) {
      print('Note: Could not delete old avatar: $e');
    }
  }

  static Future<AppUser?> getProfile(String userId) {
    return UsersRepository().getByAuthUserId(userId);
  }

}
