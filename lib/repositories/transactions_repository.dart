import '../models/transaction.dart';
import '../services/supabase_service.dart';

class TransactionsRepository {
  TransactionsRepository();

  static const _table = 'transactions';

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

  Future<Transaction> create(Transaction transaction) async {
    final response = await SupabaseService.client
        .from(_table)
        .insert(transaction.toInsertMap())
        .select()
        .single();
    final map = _requireMap(response, operation: 'create transaction');
    return Transaction.fromMap(map);
  }

  Future<Transaction?> getById(int transactionId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('transaction_id', transactionId)
        .maybeSingle();
    if (response == null) return null;
    final map = _requireMap(response, operation: 'getById');
    return Transaction.fromMap(map);
  }

  Future<void> updateStatus({
    required int transactionId,
    required String transactionStatus,
  }) async {
    final response = await SupabaseService.client
        .from(_table)
        .update({'transaction_status': transactionStatus})
        .eq('transaction_id', transactionId)
        .select('transaction_id');

    final rows = _requireListOfMaps(response, operation: 'updateStatus');
    if (rows.isEmpty) {
      throw StateError(
        'No transaction updated. This is usually caused by RLS/permissions.',
      );
    }
  }

  Future<void> updateMeetupAndStatus({
    required int transactionId,
    required String transactionStatus,
    required String address,
  }) async {
    final response = await SupabaseService.client
        .from(_table)
        .update({
          'transaction_status': transactionStatus,
          'fulfillment_method': 'meetup',
          'address': address,
        })
        .eq('transaction_id', transactionId)
        .select('transaction_id');

    final rows = _requireListOfMaps(response, operation: 'updateMeetupAndStatus');
    if (rows.isEmpty) {
      throw StateError(
        'No transaction updated. This is usually caused by RLS/permissions.',
      );
    }
  }

  Future<List<Transaction>> listForBuyer(String buyerId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('buyer_id', buyerId)
        .order('created_at', ascending: false);
    final rows = _requireListOfMaps(response, operation: 'listForBuyer');
    return rows.map<Transaction>(Transaction.fromMap).toList();
  }

  Future<List<Transaction>> listForSeller(String sellerId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    final rows = _requireListOfMaps(response, operation: 'listForSeller');
    return rows.map<Transaction>(Transaction.fromMap).toList();
  }
}

