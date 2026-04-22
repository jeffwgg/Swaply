import '../models/payment.dart';
import '../services/supabase_service.dart';

class PaymentsRepository {
  PaymentsRepository();

  static const _table = 'payments';

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

  Future<Payment> create(Payment payment) async {
    final response = await SupabaseService.client
        .from(_table)
        .insert(payment.toInsertMap())
        .select()
        .single();
    final map = _requireMap(response, operation: 'create payment');
    return Payment.fromMap(map);
  }

  Future<List<Payment>> listForTransaction(int transactionId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('transaction_id', transactionId)
        .order('created_at', ascending: false);
    final rows =
        _requireListOfMaps(response, operation: 'listForTransaction');
    return rows.map<Payment>(Payment.fromMap).toList();
  }

  Future<void> updateStatusForTransaction({
    required int transactionId,
    required String paymentStatus,
  }) async {
    final response = await SupabaseService.client
        .from(_table)
        .update({'payment_status': paymentStatus})
        .eq('transaction_id', transactionId)
        .select('payment_id');

    final rows =
        _requireListOfMaps(response, operation: 'updateStatusForTransaction');
    if (rows.isEmpty) {
      throw StateError(
        'No payment updated. This is usually caused by RLS/permissions.',
      );
    }
  }
}

