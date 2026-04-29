import 'package:sqflite/sqflite.dart' as sqlite;

import '../../models/payment.dart';
import '../../models/transaction.dart';
import '../../services/local_db_service.dart';

class LocalTransactionRow {
  final Transaction tx;
  final String? sellerUsername;
  final String? itemName;
  final String? itemImageUrl;
  final String? itemCategory;
  final String? itemStatus;
  final String? tradedItemName;
  final String? tradedItemImageUrl;
  final String? tradedItemCategory;
  final String? tradedItemStatus;
  final Payment? payment; // optional (not cached yet)

  const LocalTransactionRow({
    required this.tx,
    required this.sellerUsername,
    required this.itemName,
    required this.itemImageUrl,
    required this.itemCategory,
    required this.itemStatus,
    required this.tradedItemName,
    required this.tradedItemImageUrl,
    required this.tradedItemCategory,
    required this.tradedItemStatus,
    required this.payment,
  });
}

class LocalTransactionsRepository {
  LocalTransactionsRepository({LocalDbService? localDbService})
      : _localDbService = localDbService ?? LocalDbService.instance;

  final LocalDbService _localDbService;

  static const _table = 'transactions_cache';

  Future<void> upsertFromRemote({
    required Transaction tx,
    required String? sellerUsername,
    required String? itemName,
    required String? itemImageUrl,
    required String? itemCategory,
    required String? itemStatus,
    required String? tradedItemName,
    required String? tradedItemImageUrl,
    required String? tradedItemCategory,
    required String? tradedItemStatus,
  }) async {
    final sqlite.Database db = await _localDbService.database;

    final map = <String, Object?>{
      'transaction_id': tx.transactionId,
      'buyer_id': tx.buyerId,
      'seller_id': tx.sellerId,
      'item_id': tx.itemId,
      'traded_item_id': tx.tradedItemId,
      'transaction_type': tx.transactionType,
      'transaction_status': tx.transactionStatus,
      'item_price': tx.itemPrice,
      'shipping_fee': tx.shippingFee,
      'total_amount': tx.totalAmount,
      'fulfillment_method': tx.fulfillmentMethod,
      'address': tx.address,
      'created_at': tx.createdAt.toIso8601String(),
      'seller_username': sellerUsername,
      'item_name': itemName,
      'item_image_url': itemImageUrl,
      'item_category': itemCategory,
      'item_status': itemStatus,
      'traded_item_name': tradedItemName,
      'traded_item_image_url': tradedItemImageUrl,
      'traded_item_category': tradedItemCategory,
      'traded_item_status': tradedItemStatus,
      'is_synced': 1,
      'failed': 0,
      'last_synced_at': DateTime.now().toIso8601String(),
      'sync_error': null,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await db.insert(
      _table,
      map,
      conflictAlgorithm: sqlite.ConflictAlgorithm.replace,
    );
  }

  Future<List<LocalTransactionRow>> listForUser(String userId) async {
    final sqlite.Database db = await _localDbService.database;
    final rows = await db.query(
      _table,
      where: 'buyer_id = ? OR seller_id = ?',
      whereArgs: [userId, userId],
      orderBy: 'created_at DESC',
    );

    return rows.map((r) {
      final createdAtRaw = r['created_at']?.toString();
      final createdAt = createdAtRaw == null || createdAtRaw.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.tryParse(createdAtRaw) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      final tx = Transaction(
        transactionId: (r['transaction_id'] as num).toInt(),
        buyerId: r['buyer_id']?.toString() ?? '',
        sellerId: r['seller_id']?.toString() ?? '',
        itemId: (r['item_id'] as num).toInt(),
        tradedItemId: r['traded_item_id'] == null
            ? null
            : (r['traded_item_id'] as num).toInt(),
        transactionType: r['transaction_type']?.toString(),
        transactionStatus: r['transaction_status']?.toString(),
        itemPrice: r['item_price'] is num ? (r['item_price'] as num).toDouble() : null,
        shippingFee:
            r['shipping_fee'] is num ? (r['shipping_fee'] as num).toDouble() : null,
        totalAmount:
            r['total_amount'] is num ? (r['total_amount'] as num).toDouble() : null,
        fulfillmentMethod: r['fulfillment_method']?.toString(),
        address: r['address']?.toString(),
        cancelledBy: null,
        createdAt: createdAt,
      );

      return LocalTransactionRow(
        tx: tx,
        sellerUsername: r['seller_username']?.toString(),
        itemName: r['item_name']?.toString(),
        itemImageUrl: r['item_image_url']?.toString(),
        itemCategory: r['item_category']?.toString(),
        itemStatus: r['item_status']?.toString(),
        tradedItemName: r['traded_item_name']?.toString(),
        tradedItemImageUrl: r['traded_item_image_url']?.toString(),
        tradedItemCategory: r['traded_item_category']?.toString(),
        tradedItemStatus: r['traded_item_status']?.toString(),
        payment: null,
      );
    }).toList();
  }

  Future<LocalTransactionRow?> getById(int transactionId) async {
    final sqlite.Database db = await _localDbService.database;
    final rows = await db.query(
      _table,
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final createdAtRaw = r['created_at']?.toString();
    final createdAt = createdAtRaw == null || createdAtRaw.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.tryParse(createdAtRaw) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final tx = Transaction(
      transactionId: (r['transaction_id'] as num).toInt(),
      buyerId: r['buyer_id']?.toString() ?? '',
      sellerId: r['seller_id']?.toString() ?? '',
      itemId: (r['item_id'] as num).toInt(),
      tradedItemId: r['traded_item_id'] == null
          ? null
          : (r['traded_item_id'] as num).toInt(),
      transactionType: r['transaction_type']?.toString(),
      transactionStatus: r['transaction_status']?.toString(),
      itemPrice: r['item_price'] is num ? (r['item_price'] as num).toDouble() : null,
      shippingFee: r['shipping_fee'] is num ? (r['shipping_fee'] as num).toDouble() : null,
      totalAmount: r['total_amount'] is num ? (r['total_amount'] as num).toDouble() : null,
      fulfillmentMethod: r['fulfillment_method']?.toString(),
      address: r['address']?.toString(),
      cancelledBy: null,
      createdAt: createdAt,
    );

    return LocalTransactionRow(
      tx: tx,
      sellerUsername: r['seller_username']?.toString(),
      itemName: r['item_name']?.toString(),
      itemImageUrl: r['item_image_url']?.toString(),
      itemCategory: r['item_category']?.toString(),
      itemStatus: r['item_status']?.toString(),
      tradedItemName: r['traded_item_name']?.toString(),
      tradedItemImageUrl: r['traded_item_image_url']?.toString(),
      tradedItemCategory: r['traded_item_category']?.toString(),
      tradedItemStatus: r['traded_item_status']?.toString(),
      payment: null,
    );
  }
}

