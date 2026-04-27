import 'package:supabase_flutter/supabase_flutter.dart';

class FavouriteRepository {
  static final FavouriteRepository _instance = FavouriteRepository._internal();
  factory FavouriteRepository() => _instance;
  FavouriteRepository._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Add to favourites
  Future<void> addFavourite(String userId, int itemId) async {
    try {
      await _supabase.from('favourites').upsert({
        'user_id': userId,
        'item_id': itemId,
      }, onConflict: 'user_id,item_id');
    } catch (e) {
      throw Exception('Failed to add favourite: $e');
    }
  }

  /// Remove from favourites
  Future<void> removeFavourite(String userId, int itemId) async {
    try {
      await _supabase
          .from('favourites')
          .delete()
          .eq('user_id', userId)
          .eq('item_id', itemId);
    } catch (e) {
      throw Exception('Failed to remove favourite: $e');
    }
  }

  Future<bool> isFavourited(String userId, int itemId) async {
    try {
      final response = await _supabase
          .from('favourites')
          .select()
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .count(CountOption.exact);

      return response.count > 0;
    } catch (e) {
      throw Exception('Failed to check favourite: $e');
    }
  }

  Future<int> getUserFavouriteCount(String userId) async {
    final response = await _supabase
        .from('favourites')
        .select('item_id')
        .eq('user_id', userId)
        .count(CountOption.exact);

    return response.count;
  }

  Future<Set<int>> getUserFavouriteItemIds(String userId) async {
    final response = await _supabase
        .from('favourites')
        .select('item_id')
        .eq('user_id', userId);

    return (response as List).map((e) => e['item_id'] as int).toSet();
  }

  Future<int> getFavouriteCount(int itemId) async {
    try {
      final response = await _supabase
          .from('favourites')
          .select('*')
          .eq('item_id', itemId)
          .count(CountOption.exact);

      return response.count;
    } catch (e) {
      throw Exception('Failed to get favourite count: $e');
    }
  }

  Future<bool> toggleFavourite(String userId, int itemId) async {
    try {
      final existing = await _supabase
          .from('favourites')
          .select()
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .maybeSingle();

      if (existing != null) {
        await removeFavourite(userId, itemId);
        return false;
      } else {
        await addFavourite(userId, itemId);
        return true;
      }
    } catch (e) {
      throw Exception('Failed to toggle favourite: $e');
    }
  }

  Future<int> getTotalSavedForSeller(String sellerId) async {
    try {
      final items = await _supabase
          .from('items')
          .select('id')
          .eq('owner_id', sellerId);

      if (items.isEmpty) return 0;

      final itemIds = (items as List).map((i) => i['id'] as int).toList();
      final response = await _supabase
          .from('favourites')
          .select('id')
          .inFilter('item_id', itemIds)
          .count(CountOption.exact);

      return response.count;
    } catch (e) {
      print('Failed to get seller total saved: $e');
      return 0;
    }
  }

  Stream<List<Map<String, dynamic>>> watchFavouriteIds(String userId) {
    return _supabase
        .from('favourites')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId);
  }
}

// Added debugPrint helper
void debugPrint(String message) {
  print(message);
}
