class TransactionRequest {
  final String id;
  final String itemId;
  final String requesterId;
  final String type;
  final double? offeredPrice;
  final String? offeredItemId;
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
    return TransactionRequest(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      requesterId: map['requester_id'] as String,
      type: map['type'] as String,
      offeredPrice: (map['offered_price'] as num?)?.toDouble(),
      offeredItemId: map['offered_item_id'] as String?,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
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
