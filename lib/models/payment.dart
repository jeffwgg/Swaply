import '../core/utils/parsing.dart';

class Payment {
  final int paymentId;
  final String paymentIntentId;
  final String paymentMethod;
  final double paymentAmount;
  final String paymentStatus;
  final int transactionId;
  final DateTime createdAt;

  const Payment({
    required this.paymentId,
    required this.paymentIntentId,
    required this.paymentMethod,
    required this.paymentAmount,
    required this.paymentStatus,
    required this.transactionId,
    required this.createdAt,
  });

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      paymentId: parseInt(map['payment_id'], fieldName: 'payments.payment_id'),
      paymentIntentId: parseString(
        map['payment_intent_id'],
        fieldName: 'payments.payment_intent_id',
      ),
      paymentMethod: parseString(
        map['payment_method'],
        fieldName: 'payments.payment_method',
      ),
      paymentAmount: parseNullableDouble(
        map['payment_amount'],
        fieldName: 'payments.payment_amount',
      ) ??
          0,
      paymentStatus: parseString(
        map['payment_status'],
        fieldName: 'payments.payment_status',
      ),
      transactionId: parseInt(
        map['transaction_id'],
        fieldName: 'payments.transaction_id',
      ),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'payments.created_at',
      ),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'payment_intent_id': paymentIntentId,
      'payment_method': paymentMethod,
      'payment_amount': paymentAmount,
      'payment_status': paymentStatus,
      'transaction_id': transactionId,
    };
  }
}

