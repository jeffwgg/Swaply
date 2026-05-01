import '../repositories/follow_repository.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

class FollowService {
  static final _repo = FollowRepository();

  static Future<bool> followUser(String followerId, String followeeId) async {
    if (followerId == followeeId) {
      return false;
    }

    final alreadyFollowing = await _repo.isFollowing(followerId, followeeId);
    if (alreadyFollowing) {
      return true;
    }

    final result = await _repo.follow(followerId, followeeId);
    if (!result) {
      return false;
    }

    try {
      final profile = await SupabaseService.client
          .from('users')
          .select('username')
          .eq('id', followerId)
          .maybeSingle();
      String followerName = '';
      if (profile is Map) {
        final rawProfile = profile as Map;
        final normalizedProfile = rawProfile.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
        followerName = normalizedProfile['username']?.toString().trim() ?? '';
      }
      final displayName = followerName.isEmpty ? 'Someone' : followerName;

      await NotificationService.instance.sendNotificationToUser(
        recipientId: followeeId,
        title: 'New follower',
        body: '$displayName started following you.',
        type: 'follow',
        data: {'action': 'open_profile', 'user_id': followerId},
      );
    } catch (_) {
    }

    return result;
  }

  /// Unfollow a user
  static Future<bool> unfollowUser(String followerId, String followeeId) async {
    final result = await _repo.unfollow(followerId, followeeId);
    if (result) {
      print("Unfollowed successfully");
    } else {
      print("Unfollow failed");
    }
    return result;
  }

  /// Check if a user is following another user
  static Future<bool> isFollowing(String followerId, String followeeId) async {
    if (followerId == followeeId) return false;
    return _repo.isFollowing(followerId, followeeId);
  }

  /// Get follower count
  static Future<int> getFollowerCount(String userId) async {
    return _repo.getFollowerCount(userId);
  }

  /// Get following count
  static Future<int> getFollowingCount(String userId) async {
    return _repo.getFollowingCount(userId);
  }

  /// Get list of followers
  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    return _repo.getFollowers(userId);
  }

  /// Get list of following
  static Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    return _repo.getFollowing(userId);
  }
}
