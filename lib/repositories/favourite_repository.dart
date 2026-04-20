import 'package:supabase_flutter/supabase_flutter.dart';

class FavouriteRepository {
  static final FavouriteRepository _instance = FavouriteRepository._internal();
  factory FavouriteRepository() => _instance;
  FavouriteRepository._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Add to favourites
  Future<void> addFavourite(String userId, int itemId) async {
    try {
      await _supabase.from('favourites').insert({
        'user_id': userId,
        'item_id': itemId,
      });
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
          .maybeSingle();

      return response != null;
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

    return (response as List)
        .map((e) => e['item_id'] as int)
        .toSet();
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
      debugPrint('Error getting favourite count: $e');
      return 0;
    }
  }

  Future<bool> toggleFavourite(String userId, int itemId) async {
    final exists = await isFavourited(userId, itemId);

    if (exists) {
      await removeFavourite(userId, itemId);
      return false;
    } else {
      await addFavourite(userId, itemId);
      return true;
    }
  }
}

// Added debugPrint helper
void debugPrint(String message) {
  print(message);
}
