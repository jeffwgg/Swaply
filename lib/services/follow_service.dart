import '../repositories/follow_repository.dart';

class FollowService {
  static final _repo = FollowRepository();

  /// Follow a user
  static Future<bool> followUser(String followerId, String followeeId) async {
    final result = await _repo.follow(followerId, followeeId);
    print("DATABASE RESPONSE follow: $result");
    return result;
  }

  /// Unfollow a user
  static Future<bool> unfollowUser(String followerId, String followeeId) async {
    final result = await _repo.unfollow(followerId, followeeId);
    if (result) {
      print("✅ Unfollowed successfully");
    } else {
      print("⚠️ Unfollow failed");
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