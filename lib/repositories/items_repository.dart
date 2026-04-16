import 'dart:developer';

import '../models/item_listing.dart';
import '../services/supabase_service.dart';
import 'favourite_repository.dart';

class ItemsRepository {
  static final ItemsRepository _instance = ItemsRepository._internal();
  factory ItemsRepository() => _instance;
  ItemsRepository._internal();

  static const _table = 'items';

  List<Map<String, dynamic>> _requireListOfMaps(
    dynamic response, {
    required String operation,
  }) {
    if (response is! List) {
      throw StateError('Unexpected $operation response: expected List.');
    }

    return response.map<Map<String, dynamic>>((row) {
      if (row is Map<String, dynamic>) {
        return row;
      }
      if (row is Map) {
        return row.map((key, value) => MapEntry(key.toString(), value));
      }
      throw StateError('Unexpected $operation row shape: expected Map.');
    }).toList();
  }

  Future<List<ItemListing>> getDiscoverList({
    int? userId,
    String? category,
    String? listingType,
    String? searchQuery,
  }) async {
    log(userId.toString());
    var query = SupabaseService.client
        .from(_table)
        .select()
        .eq('status', 'available')
        .filter('replied_to', 'is', null);

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.ilike('name', '%$searchQuery%');
    }else{
      // Exclude items owned by the current user by default
      if (userId != null) {
        query = query.neq('owner_id', userId);
      }
    }

    if (category != null && category != 'All') {
      query = query.eq('category', category);
    }

    if (listingType != null && listingType != 'both') {
      if (listingType == 'sell') {
        query = query.or('listing_type.eq.sell,listing_type.eq.both');
      } else if (listingType == 'trade') {
        query = query.or('listing_type.eq.trade,listing_type.eq.both');
      }
    }

    final response = await query.order('created_at', ascending: false);

    final rows = _requireListOfMaps(response, operation: 'getDiscoverList');
    List<ItemListing> items = rows
        .map<ItemListing>(ItemListing.fromMap)
        .toList();

    if (userId != null) {
      final favIds = await FavouriteRepository().getUserFavouriteItemIds(
        userId,
      );

      for (var item in items) {
        item.isFavorite = favIds.contains(item.id);
      }
    }

    return items;
  }

  Future<int?> getLastId() async {
    final response = await SupabaseService.client
        .from(_table)
        .select('id')
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return response['id'] as int?;
  }

  Future<void> create(ItemListing item) async {
    await SupabaseService.client.from(_table).insert(item.toMap());
  }

  Future<void> update(ItemListing item) async {
    await SupabaseService.client
        .from(_table)
        .update(item.toMap())
        .eq('id', item.id);
  }

  Future<List<ItemListing>> getReplyList(int id) async {
    var query = SupabaseService.client
        .from(_table)
        .select()
        .eq('replied_to', id);

    final response = await query.order('created_at', ascending: false);
    final rows = _requireListOfMaps(response, operation: 'getReplyList');
    return rows.map<ItemListing>(ItemListing.fromMap).toList();
  }

  Future<void> dropListing(int id) async {
    await SupabaseService.client
        .from(_table)
        .update({'status': 'dropped'})
        .eq('id', id);
  }
}
