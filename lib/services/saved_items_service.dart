import 'supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

//favourite 过后改
class SavedItemsService {
  /// Add item to saved/favorites
  static Future<bool> saveItem(String userId, String itemId) async {
    try {
      await SupabaseService.client.from('saved_items').insert({
        'user_id': userId,
        'item_id': itemId,
      });
      return true;
    } catch (e) {
      print('Error saving item: $e');
      return false;
    }
  }

  /// Remove item from saved/favorites
  static Future<bool> unsaveItem(String userId, String itemId) async {
    try {
      await SupabaseService.client
          .from('saved_items')
          .delete()
          .eq('user_id', userId)
          .eq('item_id', itemId);
      return true;
    } catch (e) {
      print('Error unsaving item: $e');
      return false;
    }
  }

  /// Check if item is saved by user
  static Future<bool> isItemSaved(String userId, String itemId) async {
    try {
      final result = await SupabaseService.client
          .from('saved_items')
          .select()
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .maybeSingle();
      return result != null;
    } catch (e) {
      print('Error checking saved status: $e');
      return false;
    }
  }

  /// Get total saved count for a user (all their items' combined saves)
  static Future<int> getTotalSavedCount(String userId) async {
    try {
      // Get all items owned by this user
      final userItems = await SupabaseService.client
          .from('items')
          .select('id')
          .eq('owner_id', userId);

      if (userItems.isEmpty) return 0;

      final itemIds = List<String>.from(
        userItems.map((item) => item['id'] as String),
      );

      // Count total saves across all these items
      final result = await SupabaseService.client
          .from('saved_items')
          .select()
          .inFilter('item_id', itemIds)
          .count(CountOption.exact);

      return result.count;
    } catch (e) {
      print('Error getting total saved count: $e');
      return 0;
    }
  }

  /// Get saved count for a specific item
  static Future<int> getItemSavedCount(String itemId) async {
    try {
      final result = await SupabaseService.client
          .from('saved_items')
          .select()
          .eq('item_id', itemId)
          .count(CountOption.exact);
      return result.count;
    } catch (e) {
      print('Error getting item saved count: $e');
      return 0;
    }
  }

  /// Get list of users who saved an item
  static Future<List<Map<String, dynamic>>> getItemSavedBy(String itemId) async {
    try {
      final result = await SupabaseService.client
          .from('saved_items')
          .select('user_id, users!inner(id, username, avatar_url)')
          .eq('item_id', itemId);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('Error getting item saved by: $e');
      return [];
    }
  }

  /// Get user's saved items
  static Future<List<Map<String, dynamic>>> getUserSavedItems(String userId) async {
    try {
      final result = await SupabaseService.client
          .from('saved_items')
          .select('item_id, items!inner(id, name, image_urls, owner_id)')
          .eq('user_id', userId);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('Error getting user saved items: $e');
      return [];
    }
  }
}
