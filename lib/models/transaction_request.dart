import '../core/utils/parsing.dart';

class TransactionRequest {
  final int id;
  final int itemId;
  final int requesterId;
  final String type;
  final double? offeredPrice;
  final int? offeredItemId;
  final String status;
  final DateTime createdAt;

  const TransactionRequest({
    required this.id,
    required this.itemId,
    required this.requesterId,
    required this.type,
    this.offeredPrice,
    this.offeredItemId,
    required this.status,
    required this.createdAt,
  });

  factory TransactionRequest.fromMap(Map<String, dynamic> map) {
    DateTime parseDateTime(dynamic value) {
      if (value is DateTime) {
        return value;
      }
      return DateTime.parse(value as String);
    }

    return TransactionRequest(
      id: parseInt(map['id'], fieldName: 'transaction_requests.id'),
      itemId: parseInt(
        map['item_id'],
        fieldName: 'transaction_requests.item_id',
      ),
      requesterId: parseInt(
        map['requester_id'],
        fieldName: 'transaction_requests.requester_id',
      ),
      type: map['type'] as String,
      offeredPrice: (map['offered_price'] as num?)?.toDouble(),
      offeredItemId: parseNullableInt(
        map['offered_item_id'],
        fieldName: 'transaction_requests.offered_item_id',
      ),
      status: map['status'] as String,
      createdAt: parseDateTime(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'requester_id': requesterId,
      'type': type,
      'offered_price': offeredPrice,
      'offered_item_id': offeredItemId,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
