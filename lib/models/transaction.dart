import '../core/utils/parsing.dart';

class Transaction {
  final int transactionId;
  final String buyerId;
  final String sellerId;
  final int itemId;
  final int? tradedItemId;
  final String? transactionType;
  final String? transactionStatus;
  final double? itemPrice;
  final double? shippingFee;
  final double? totalAmount;
  final String? fulfillmentMethod;
  final String? address;
  final String? cancelledBy; // 'buyer' | 'seller'
  final DateTime createdAt;

  const Transaction({
    required this.transactionId,
    required this.buyerId,
    required this.sellerId,
    required this.itemId,
    required this.tradedItemId,
    required this.transactionType,
    required this.transactionStatus,
    required this.itemPrice,
    required this.shippingFee,
    required this.totalAmount,
    required this.fulfillmentMethod,
    required this.address,
    required this.cancelledBy,
    required this.createdAt,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      transactionId: parseInt(
        map['transaction_id'],
        fieldName: 'transactions.transaction_id',
      ),
      buyerId: parseString(map['buyer_id'], fieldName: 'transactions.buyer_id'),
      sellerId: parseString(
        map['seller_id'],
        fieldName: 'transactions.seller_id',
      ),
      itemId: parseInt(map['item_id'], fieldName: 'transactions.item_id'),
      tradedItemId: parseNullableInt(
        map['traded_item_id'],
        fieldName: 'transactions.traded_item_id',
      ),
      transactionType: parseNullableString(
        map['transaction_type'],
        fieldName: 'transactions.transaction_type',
      ),
      transactionStatus: parseNullableString(
        map['transaction_status'],
        fieldName: 'transactions.transaction_status',
      ),
      itemPrice: parseNullableDouble(
        map['item_price'],
        fieldName: 'transactions.item_price',
      ),
      shippingFee: parseNullableDouble(
        map['shipping_fee'],
        fieldName: 'transactions.shipping_fee',
      ),
      totalAmount: parseNullableDouble(
        map['total_amount'],
        fieldName: 'transactions.total_amount',
      ),
      fulfillmentMethod: parseNullableString(
        map['fulfillment_method'],
        fieldName: 'transactions.fulfillment_method',
      ),
      address: parseNullableString(map['address'], fieldName: 'transactions.address'),
      cancelledBy: parseNullableString(
        map['cancelled_by'],
        fieldName: 'transactions.cancelled_by',
      ),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'transactions.created_at',
      ),
    );
  }

  /// For inserting a row into `transactions`.
  Map<String, dynamic> toInsertMap() {
    return {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'item_id': itemId,
      'traded_item_id': tradedItemId,
      'transaction_type': transactionType,
      'transaction_status': transactionStatus,
      'item_price': itemPrice,
      'shipping_fee': shippingFee,
      'total_amount': totalAmount,
      'fulfillment_method': fulfillmentMethod,
      'address': address,
      'cancelled_by': cancelledBy,
    };
  }
}

