import '../models/item_listing.dart';
import '../services/supabase_service.dart';

class ItemsRepository {
  ItemsRepository();

  static const _table = 'items';

  Future<List<ItemListing>> listAvailable({String? ownerId}) async {
    var query = SupabaseService.client
        .from(_table)
        .select()
        .eq('status', 'available');

    if (ownerId != null && ownerId.isNotEmpty) {
      query = query.eq('owner_id', ownerId);
    }

    final response = await query.order('created_at', ascending: false);
    return response.map<ItemListing>(ItemListing.fromMap).toList();
  }

  Future<ItemListing?> getById(String id) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return ItemListing.fromMap(response);
  }

  Future<void> create(ItemListing item) async {
    await SupabaseService.client.from(_table).insert(item.toMap());
  }

  Future<void> updateStatus({
    required String itemId,
    required String status,
  }) async {
    await SupabaseService.client
        .from(_table)
        .update({'status': status})
        .eq('id', itemId);
  }
}
