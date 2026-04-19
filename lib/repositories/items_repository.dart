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

    try {
      List<int> matchedUserIds = [];
      
      // find user id whose username matches
      if (searchQuery != null && searchQuery.isNotEmpty) {
        try {
          final usersRes = await SupabaseService.client
              .from('users')
              .select('id')
              .ilike('username', '%$searchQuery%');
          
          if (usersRes is List) {
            matchedUserIds = usersRes.map((u) => u['id'] as int).toList();
          }
        } catch (e) {
          log('User search error: $e');
        }
      }

      var queryBuilder = SupabaseService.client
          .from(_table)
          .select('*, users(username)');

      // search item name
      if (searchQuery != null && searchQuery.isNotEmpty) {
        String orClause = 'name.ilike.%$searchQuery%';

        if (matchedUserIds.isNotEmpty) {
          final idsString = matchedUserIds.join(',');
          orClause += ',owner_id.in.($idsString)';
        }
        
        queryBuilder = queryBuilder.or(orClause);
      }

      queryBuilder = queryBuilder
          .eq('status', 'available')
          .filter('replied_to', 'is', null);

      if (searchQuery == null || searchQuery.isEmpty) {
        // exclude items owned by the current user by default when not searching
        if (userId != null) {
          queryBuilder = queryBuilder.neq('owner_id', userId);
        }
      }

      if (category != null && category != 'All') {
        queryBuilder = queryBuilder.eq('category', category);
      }

      if (listingType != null && listingType != 'both') {
        if (listingType == 'sell') {
          queryBuilder = queryBuilder.or(
            'listing_type.eq.sell,listing_type.eq.both',
          );
        } else if (listingType == 'trade') {
          queryBuilder = queryBuilder.or(
            'listing_type.eq.trade,listing_type.eq.both',
          );
        }
      }

      final response = await queryBuilder.order('created_at', ascending: false);

      final rows = _requireListOfMaps(response, operation: 'getDiscoverList');
      List<ItemListing> items = rows
          .map<ItemListing>(ItemListing.fromMap)
          .toList();

      // Step 5: Handle favorites
      if (userId != null) {
        final favIds = await FavouriteRepository().getUserFavouriteItemIds(
          userId,
        );

        for (var item in items) {
          item.isFavorite = favIds.contains(item.id);
        }
      }

      return items;
    } catch (e) {
      log('getDiscoverList error: $e');
    }

    return [];
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
    await SupabaseService.client.from(_table).insert(item.toInsertMap());
  }

  Future<void> update(ItemListing item) async {
    await SupabaseService.client
        .from(_table)
        .update(item.toInsertMap())
        .eq('id', item.id);
  }

  Future<List<ItemListing>> getReplyList(int id) async {
    var query = SupabaseService.client
        .from(_table)
        .select()
        .neq('status', 'dropped')
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

  Future<void> updateStatus(String s, int id) async {
    await SupabaseService.client
        .from(_table)
        .update({'status': s})
        .eq('id', id);
  }

  Future<List<ItemListing>> getUserItems(int userId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
    
    final rows = _requireListOfMaps(response, operation: 'getUserItems');
    return rows.map<ItemListing>(ItemListing.fromMap).toList();
  }

  Future<List<ItemListing>> getFavouriteItems(int userId) async {
    final favIds = await FavouriteRepository().getUserFavouriteItemIds(userId);
    if (favIds.isEmpty) return [];

    final response = await SupabaseService.client
        .from(_table)
        .select()
        .inFilter('id', favIds.toList())
        .order('created_at', ascending: false);
    
    final rows = _requireListOfMaps(response, operation: 'getFavouriteItems');
    final items = rows.map<ItemListing>(ItemListing.fromMap).toList();
    for (var item in items) {
      item.isFavorite = true;
    }
    return items;
  }

  Future<ItemListing?> getById(int id) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
    
    if (response == null) return null;
    return ItemListing.fromMap(response);
  }
}
