import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/item_listing.dart';
import '../../services/local_db_service.dart';

class LocalProfileItemsRepository {
  LocalProfileItemsRepository({LocalDbService? localDbService})
    : _localDbService = localDbService ?? LocalDbService.instance;

  final LocalDbService _localDbService;

  Future<void> replaceItems({
    required String userId,
    required String tabKey,
    required List<ItemListing> items,
  }) async {
    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        'profile_items_cache',
        where: 'user_id = ? AND tab_key = ?',
        whereArgs: [userId, tabKey],
      );

      for (final item in items) {
        await txn.insert('profile_items_cache', {
          'user_id': userId,
          'tab_key': tabKey,
          'item_id': item.id,
          'payload': jsonEncode(item.toMap()),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<ItemListing>> listItems({
    required String userId,
    required String tabKey,
  }) async {
    final db = await _localDbService.database;
    final rows = await db.query(
      'profile_items_cache',
      columns: ['payload'],
      where: 'user_id = ? AND tab_key = ?',
      whereArgs: [userId, tabKey],
      orderBy: 'updated_at DESC, item_id DESC',
    );

    return rows
        .map((row) {
          final payload = row['payload'] as String?;
          if (payload == null || payload.isEmpty) return null;
          final map = jsonDecode(payload) as Map<String, dynamic>;
          return ItemListing.fromMap(map);
        })
        .whereType<ItemListing>()
        .toList(growable: false);
  }
}
