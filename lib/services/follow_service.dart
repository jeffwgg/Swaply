import 'supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:postgrest/postgrest.dart';

class FollowService {
  /// Follow a user
  static Future<bool> followUser(String followerId, String followeeId) async {
  try {
    await SupabaseService.client.from('follows').insert({
      'follower_id': followerId, 
      'followee_id': followeeId, 
    });
    return true;
  } catch (e) {
    print('Error: $e');
    return false;
  }
}

  /// Unfollow a user
  static Future<bool> unfollowUser(String followerId, String followeeId) async {
    try {
      await SupabaseService.client
          .from('follows')
          .delete()
          .eq('follower_id', followerId)
          .eq('followee_id', followeeId);
      return true;
    } catch (e) {
      print('Error unfollowing user: $e');
      return false;
    }
  }

  /// Check if a user is following another user
  static Future<bool> isFollowing(String followerId, String followeeId) async {
    try {
      final result = await SupabaseService.client
          .from('follows')
          .select()
          .eq('follower_id', followerId)
          .eq('followee_id', followeeId)
          .maybeSingle();
      return result != null;
    } catch (e) {
      print('Error checking follow status: $e');
      return false;
    }
  }

  /// Get follower count
  static Future<int> getFollowerCount(String userId) async {
    try {
      // 使用 head: true 表示只取数量，不取数据，性能最好
      final response = await SupabaseService.client
          .from('follows')
          .select('*') 
          .eq('followee_id', userId)
          .count(CountOption.exact); // 如果这里还是报错，请看下方的最终方案
          
      return response.count;
    } catch (e) {
      print('Error getting follower count: $e');
      return 0;
    }
  }

  /// Get following count
  static Future<int> getFollowingCount(String userId) async {
    try {
      final result = await SupabaseService.client
          .from('follows')
          .select()
          .eq('follower_id', userId)
          .count(CountOption.exact);
      return result.count;
    } catch (e) {
      print('Error getting following count: $e');
      return 0;
    }
  }

  /// Get list of followers
  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {
      final result = await SupabaseService.client
          .from('follows')
          .select('follower_id, users!inner(id, username, avatar_url)')
          .eq('followee_id', userId);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('Error getting followers: $e');
      return [];
    }
  }

  /// Get list of following
  static Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {
      final result = await SupabaseService.client
          .from('follows')
          .select('followee_id, users!inner(id, username, avatar_url)')
          .eq('follower_id', userId);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('Error getting following: $e');
      return [];
    }
  }
}
