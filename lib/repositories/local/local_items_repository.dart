import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/item_listing.dart';
import '../../models/offline_action.dart';
import '../../services/local_db_service.dart';

class LocalItemsRepository {
  LocalItemsRepository({LocalDbService? localDbService})
      : _localDbService = localDbService ?? LocalDbService.instance;

  final LocalDbService _localDbService;

  Map<String, dynamic> _itemToDbMap(ItemListing item) {
    return {
      'id': item.id,
      'name': item.name,
      'description': item.description,
      'price': item.price,
      'listing_type': item.listingType,
      'owner_id': item.ownerId,
      'status': item.status,
      'category': item.category,
      'image_urls': jsonEncode(item.imageUrls),
      'preference': item.preference,
      'replied_to': item.repliedTo,
      'address': item.address,
      'latitude': item.latitude,
      'longitude': item.longitude,
      'created_at': item.createdAt.toIso8601String(),
      'last_synced_at': DateTime.now().toIso8601String(),
    };
  }

  ItemListing _itemFromDbMap(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from(row);
    final rawImages = data['image_urls'];
    if (rawImages is String && rawImages.isNotEmpty) {
      data['image_urls'] = List<String>.from(jsonDecode(rawImages) as List);
    } else if (rawImages == null) {
      data['image_urls'] = <String>[];
    }
    return ItemListing.fromMap(data);
  }

  Future<List<ItemListing>> getCachedItems() async {
    final db = await _localDbService.database;
    final rows = await db.query('items_cache', orderBy: 'created_at DESC');
    return rows.map(_itemFromDbMap).toList();
  }

  Future<void> replaceCache(List<ItemListing> items) async {
    final db = await _localDbService.database;
    await db.transaction((txn) async {
      await txn.delete('items_cache');
      for (final item in items) {
        await txn.insert(
          'items_cache',
          _itemToDbMap(item),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> mergeCache(List<ItemListing> items) async {
    final db = await _localDbService.database;
    await db.transaction((txn) async {
      for (final item in items) {
        await txn.insert(
          'items_cache',
          _itemToDbMap(item),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> insertUserItem(ItemListing item) async {
    final db = await _localDbService.database;
    await db.insert(
      'user_items',
      {
        ..._itemToDbMap(item),
        'is_trade_offer': item.repliedTo != null ? 1 : 0,
        'is_synced': 1,
        'is_deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ItemListing>> getUserItems(String userId) async {
    final db = await _localDbService.database;
    final rows = await db.query(
      'user_items',
      where: 'owner_id = ? AND is_deleted = 0',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_itemFromDbMap).toList();
  }

  Future<void> replaceUserItems(List<ItemListing> items) async {
    final db = await _localDbService.database;
    await db.transaction((txn) async {
      await txn.delete('user_items');
      for (final item in items) {
        await txn.insert(
          'user_items',
          {
            ..._itemToDbMap(item),
            'is_trade_offer': item.repliedTo != null ? 1 : 0,
            'is_synced': 1,
            'is_deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<OfflineAction>> getPendingActions() async {
    final db = await _localDbService.database;
    final res = await db.query(
      'offline_actions',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );

    return res.map((e) => OfflineAction.fromMap(e)).toList();
  }

  Future<void> markSynced(int id) async {
    final db = await _localDbService.database;
    await db.update(
      'offline_actions',
      {
        'status': 'synced',
        'last_attempt_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(int id, int retryCount) async {
    final db = await _localDbService.database;
    await db.update(
      'offline_actions',
      {
        'status': retryCount >= 5 ? 'failed' : 'pending',
        'retry_count': retryCount + 1,
        'last_attempt_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markProcessing(int id) async {
    final db = await _localDbService.database;
    await db.update(
      'offline_actions',
      {'status': 'syncing'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

