import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/app_user.dart';
import 'package:sqflite/sqflite.dart';
import '/services/local_db_service.dart';

class LocalProfileRepository {
  static final LocalProfileRepository _instance = LocalProfileRepository._internal();
  factory LocalProfileRepository() => _instance;
  LocalProfileRepository._internal();

  // ── Remember Me ──────────────────────────────────────
  Future<void> saveRememberMe(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('remember_me_email', email);
    await prefs.setBool('remember_me', true);
  }

  Future<void> clearRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_me_email');
    await prefs.setBool('remember_me', false);
  }

  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final isRemembered = prefs.getBool('remember_me') ?? false;
    if (!isRemembered) return null;
    return prefs.getString('remember_me_email');
  }

  // ── Cache Profile ─────────────────────────────────────
  Future<void> saveProfile(AppUser user) async {
    final db = await LocalDbService.instance.database;
    await db.insert(
      'user_profiles',
      {
        'id': user.id,
        'username': user.username,
        'full_name': user.fullName,
        'bio': user.bio,
        'profile_image': user.profileImage,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AppUser?> getCachedProfile(String userId) async {
    final db = await LocalDbService.instance.database;
    final result = await db.query(
      'user_profiles',
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (result.isEmpty) return null;

    final row = result.first;
    return AppUser(
      id: row['id'] as String,
      username: row['username'] as String? ?? '',
      email: '',
      fullName: row['full_name'] as String?,
      bio: row['bio'] as String?,
      profileImage: row['profile_image'] as String?,
      createdAt: DateTime.now(),
    );
  }

  Future<String?> cacheProfileImage(String userId, String imageUrl) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/profile_$userId.jpg';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }
      return null;
    } catch (e) {
      print('Error caching profile image: $e');
      return null;
    }
  }

// 读取本地图片路径
  Future<String?> getCachedImagePath(String userId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/profile_$userId.jpg';
      final file = File(filePath);
      if (await file.exists()) return filePath;
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> saveStats(String userId, int following, int followers, int saved) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('stats_following_$userId', following);
    await prefs.setInt('stats_followers_$userId', followers);
    await prefs.setInt('stats_saved_$userId', saved);
  }

  Future<Map<String, int>?> getCachedStats(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final following = prefs.getInt('stats_following_$userId');
    final followers = prefs.getInt('stats_followers_$userId');
    final saved = prefs.getInt('stats_saved_$userId');

    if (following == null || followers == null || saved == null) return null;

    return {
      'following': following,
      'followers': followers,
      'saved': saved,
    };
  }
}