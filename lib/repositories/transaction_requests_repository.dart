import '../models/transaction_request.dart';
import '../services/supabase_service.dart';

class TransactionRequestsRepository {
  TransactionRequestsRepository();

  static const _table = 'transaction_requests';

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

  Future<List<TransactionRequest>> listForItem(int itemId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('item_id', itemId)
        .order('created_at', ascending: false);

    final rows = _requireListOfMaps(response, operation: 'listForItem');
    return rows.map<TransactionRequest>(TransactionRequest.fromMap).toList();
  }

  Future<List<TransactionRequest>> listForRequester(int requesterId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('requester_id', requesterId)
        .order('created_at', ascending: false);

    final rows = _requireListOfMaps(response, operation: 'listForRequester');
    return rows.map<TransactionRequest>(TransactionRequest.fromMap).toList();
  }

  Future<void> create(TransactionRequest request) async {
    await SupabaseService.client.from(_table).insert(request.toInsertMap());
  }

  Future<void> updateStatus({
    required int requestId,
    required String status,
  }) async {
    await SupabaseService.client
        .from(_table)
        .update({'status': status})
        .eq('id', requestId);
  }
}
