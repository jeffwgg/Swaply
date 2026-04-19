import '../core/utils/parsing.dart';

class TransactionRequest {
  final int id;
  final int itemId;
  final String requesterId;
  final String recipientId;
  final String type;
  final double? offeredPrice;
  final int? offeredItemId;
  final String status;
  final DateTime createdAt;

  const TransactionRequest({
    required this.id,
    required this.itemId,
    required this.requesterId,
    required this.recipientId,
    required this.type,
    this.offeredPrice,
    this.offeredItemId,
    required this.status,
    required this.createdAt,
  });

  /// Row to insert via [TransactionRequestsRepository.create] (`id` / `createdAt` are ignored by Supabase defaults).
  factory TransactionRequest.insertPurchase({
    required int itemId,
    required int requesterId,
    required double offeredPrice,
  }) {
    return TransactionRequest(
      id: 0,
      itemId: itemId,
      requesterId: requesterId,
      type: 'purchase',
      offeredPrice: offeredPrice,
      offeredItemId: null,
      status: 'pending',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  factory TransactionRequest.fromMap(Map<String, dynamic> map) {
    return TransactionRequest(
      id: parseInt(map['id'], fieldName: 'transaction_requests.id'),
      itemId: parseInt(
        map['item_id'],
        fieldName: 'transaction_requests.item_id',
      ),
      requesterId: parseString(
        map['requester_id'],
        fieldName: 'transaction_requests.requester_id',
      ),
      recipientId: parseString(
        map['recipient_id'],
        fieldName: 'transaction_requests.recipient_id',
      ),
      type: parseString(map['type'], fieldName: 'transaction_requests.type'),
      offeredPrice: parseNullableDouble(
        map['offered_price'],
        fieldName: 'transaction_requests.offered_price',
      ),
      offeredItemId: parseNullableInt(
        map['offered_item_id'],
        fieldName: 'transaction_requests.offered_item_id',
      ),
      status: parseString(
        map['status'],
        fieldName: 'transaction_requests.status',
      ),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'transaction_requests.created_at',
      ),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'item_id': itemId,
      'requester_id': requesterId,
      'recipient_id': recipientId,
      'type': type,
      'offered_price': offeredPrice,
      'offered_item_id': offeredItemId,
      'status': status,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'requester_id': requesterId,
      'recipient_id': recipientId,
      'type': type,
      'offered_price': offeredPrice,
      'offered_item_id': offeredItemId,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
