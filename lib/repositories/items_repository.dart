import '../models/item_listing.dart';
import '../services/supabase_service.dart';

class ItemsRepository {
  ItemsRepository();

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

  Map<String, dynamic> _requireMap(
    dynamic response, {
    required String operation,
  }) {
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    throw StateError('Unexpected $operation response: expected Map.');
  }

  Future<List<ItemListing>> listAvailable({int? ownerId}) async {
    var query = SupabaseService.client
        .from(_table)
        .select()
        .eq('status', 'available');

    if (ownerId != null) {
      query = query.eq('owner_id', ownerId);
    }

    final response = await query.order('created_at', ascending: false);
    final rows = _requireListOfMaps(response, operation: 'listAvailable');
    return rows.map<ItemListing>(ItemListing.fromMap).toList();
  }

  Future<ItemListing?> getById(int id) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return ItemListing.fromMap(_requireMap(response, operation: 'getById'));
  }

  Future<void> create(ItemListing item) async {
    await SupabaseService.client.from(_table).insert(item.toInsertMap());
  }

  Future<void> updateStatus({
    required int itemId,
    required String status,
  }) async {
    await SupabaseService.client
        .from(_table)
        .update({'status': status})
        .eq('id', itemId);
  }
}
