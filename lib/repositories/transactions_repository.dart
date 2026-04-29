import '../models/transaction.dart';
import '../services/notification_service.dart';
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
    final created = Transaction.fromMap(map);
    await _notifyTransactionStatus(
      transaction: created,
      status: created.transactionStatus ?? 'pending',
      event: 'created',
    );
    return created;
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
    String? cancelledBy,
  }) async {
    final update = <String, dynamic>{
      'transaction_status': transactionStatus,
      if (cancelledBy != null) 'cancelled_by': cancelledBy,
    };
    final response = await SupabaseService.client
        .from(_table)
        .update(update)
        .eq('transaction_id', transactionId)
        .select()
        .maybeSingle();

    if (response == null) {
      throw StateError(
        'No transaction updated. This is usually caused by RLS/permissions.',
      );
    }

    final transaction = Transaction.fromMap(
      _requireMap(response, operation: 'updateStatus'),
    );
    await _notifyTransactionStatus(
      transaction: transaction,
      status: transactionStatus,
      event: 'updated',
    );
  }

  Future<void> updateMeetupAndStatus({
    required int transactionId,
    required String transactionStatus,
    required String address,
    String? cancelledBy,
  }) async {
    final response = await SupabaseService.client
        .from(_table)
        .update({
          'transaction_status': transactionStatus,
          'fulfillment_method': 'meetup',
          'address': address,
          if (cancelledBy != null) 'cancelled_by': cancelledBy,
        })
        .eq('transaction_id', transactionId)
        .select()
        .maybeSingle();

    if (response == null) {
      throw StateError(
        'No transaction updated. This is usually caused by RLS/permissions.',
      );
    }

    final transaction = Transaction.fromMap(
      _requireMap(response, operation: 'updateMeetupAndStatus'),
    );
    await _notifyTransactionStatus(
      transaction: transaction,
      status: transactionStatus,
      event: 'updated',
    );
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

  Future<void> _notifyTransactionStatus({
    required Transaction transaction,
    required String status,
    required String event,
  }) async {
    final normalized = status.trim().toLowerCase();

    String title;
    String body;
    switch (normalized) {
      case 'pending':
        title = 'Transaction request';
        body = 'A new transaction request has been created.';
        break;
      case 'confirmed':
        title = 'Transaction confirmed';
        body = 'A transaction request has been confirmed.';
        break;
      case 'completed':
        title = 'Transaction completed';
        body = 'This transaction has been marked as completed.';
        break;
      default:
        return;
    }

    final recipients = <String>{transaction.buyerId, transaction.sellerId}
      ..removeWhere((id) => id.trim().isEmpty);

    if (recipients.isEmpty) {
      return;
    }

    final payload = <String, dynamic>{
      'action': 'open_transaction',
      'transaction_id': transaction.transactionId,
      'status': normalized,
      'event': event,
      'item_id': transaction.itemId,
      if (transaction.tradedItemId != null)
        'traded_item_id': transaction.tradedItemId,
    };

    for (final recipientId in recipients) {
      try {
        await NotificationService.instance.sendNotificationToUser(
          recipientId: recipientId,
          title: title,
          body: body,
          type: 'transaction',
          data: payload,
        );
      } catch (_) {
        // Do not block transaction writes when notification insertion fails.
      }
    }
  }
}
