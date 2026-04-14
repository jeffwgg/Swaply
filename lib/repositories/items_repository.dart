import '../models/item_listing.dart';
import '../services/supabase_service.dart';

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
    String? category,
    String? listingType,
  }) async {
    var query = SupabaseService.client
        .from(_table)
        .select()
        .eq('status', 'available')
        .filter('replied_to', 'is', null);

    if (category != null && category != 'All') {
      query = query.eq('category', category);
    }

    if (listingType != null && listingType != 'both') {
      if (listingType == 'sell') {
        // Use .or() if .in_() is not available in your version
        query = query.or('listing_type.eq.sell,listing_type.eq.both');
      } else if (listingType == 'trade') {
        query = query.or('listing_type.eq.trade,listing_type.eq.both');
      }
    }

    final response = await query.order('created_at', ascending: false);
    final rows = _requireListOfMaps(response, operation: 'getDiscoverList');
    return rows.map<ItemListing>(ItemListing.fromMap).toList();
  }

  Future<String?> getLastId() async {
    final response = await SupabaseService.client
        .from(_table)
        .select('id')
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return response['id'] as String?;
  }

  Future<void> create(ItemListing item) async {
    await SupabaseService.client.from(_table).insert(item.toMap());
  }
}
