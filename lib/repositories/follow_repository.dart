import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:postgrest/postgrest.dart';
import '../services/supabase_service.dart';

class FollowRepository {
  final _client = SupabaseService.client;

  Future<bool> follow(String followerId, String followeeId) async {
    try {
      await _client
          .from('follows')
          .insert({'follower_id': followerId, 'followee_id': followeeId});
      return true;
    } catch (e) {
      if (e.toString().contains('23505') || e.toString().contains('duplicate')) {
        return true;
      }
      print('❌ follow error: $e');
      return false;
    }
  }

  Future<bool> unfollow(String followerId, String followeeId) async {
    try {
      await _client
          .from('follows')
          .delete()
          .eq('follower_id', followerId)
          .eq('followee_id', followeeId);
      return true;
    } catch (e) {
      print('❌ unfollow error: $e');
      return false;
    }
  }

  Future<bool> isFollowing(String followerId, String followeeId) async {
    try {
      final result = await _client
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

  Future<int> getFollowerCount(String userId) async {
    try {
      final response = await _client
          .from('follows')
          .select('*')
          .eq('followee_id', userId)
          .count(CountOption.exact);
      return response.count;
    } catch (e) {
      print('Error getting follower count: $e');
      return 0;
    }
  }

  Future<int> getFollowingCount(String userId) async {
    try {
      final result = await _client
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

  Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {

      final follows = await _client
          .from('follows')
          .select('follower_id')
          .eq('followee_id', userId);

      final List<Map<String, dynamic>> result = [];
      for (final row in follows) {
        final followerId = row['follower_id'] as String;
        final user = await _client
            .from('users')
            .select('id, username, profile_image')
            .eq('id', followerId)
            .maybeSingle();
        if (user != null) {
          result.add({
            'follower_id': followerId,
            'follower': user,
          });
        }
      }
      return result;
    } catch (e) {
      print('Error getting followers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {

      final follows = await _client
          .from('follows')
          .select('followee_id')
          .eq('follower_id', userId);

      final List<Map<String, dynamic>> result = [];
      for (final row in follows) {
        final followeeId = row['followee_id'] as String;
        final user = await _client
            .from('users')
            .select('id, username, profile_image')
            .eq('id', followeeId)
            .maybeSingle();
        if (user != null) {
          result.add({
            'followee_id': followeeId,
            'followee': user,
          });
        }
      }
      return result;
    } catch (e) {
      print('❌ Error getting following: $e');
      return [];
    }
  }
}