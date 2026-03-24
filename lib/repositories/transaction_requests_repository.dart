import '../models/transaction_request.dart';
import '../services/supabase_service.dart';

class TransactionRequestsRepository {
  TransactionRequestsRepository();

  static const _table = 'transaction_requests';

  Future<List<TransactionRequest>> listForItem(String itemId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('item_id', itemId)
        .order('created_at', ascending: false);

    return response
        .map<TransactionRequest>(TransactionRequest.fromMap)
        .toList();
  }

  Future<List<TransactionRequest>> listForRequester(String requesterId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('requester_id', requesterId)
        .order('created_at', ascending: false);

    return response
        .map<TransactionRequest>(TransactionRequest.fromMap)
        .toList();
  }

  Future<void> create(TransactionRequest request) async {
    await SupabaseService.client.from(_table).insert(request.toMap());
  }

  Future<void> updateStatus({
    required String requestId,
    required String status,
  }) async {
    await SupabaseService.client
        .from(_table)
        .update({'status': status})
        .eq('id', requestId);
  }
}
