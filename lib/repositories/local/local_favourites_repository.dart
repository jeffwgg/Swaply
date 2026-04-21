import 'package:sqflite/sqflite.dart';

import '../../services/local_db_service.dart';

class LocalFavouritesRepository {
  LocalFavouritesRepository({LocalDbService? localDbService})
      : _localDbService = localDbService ?? LocalDbService.instance;

  final LocalDbService _localDbService;

  Future<bool> isFavourite(String userId, int itemId) async {
    final db = await _localDbService.database;

    final result = await db.query(
      'favourites',
      where: 'user_id = ? AND item_id = ? AND is_deleted = 0',
      whereArgs: [userId, itemId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<void> insert(String userId, int itemId) async {
    final db = await _localDbService.database;

    await db.insert(
      'favourites',
      {
        'user_id': userId,
        'item_id': itemId,
        'is_deleted': 0,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markDeleted(String userId, int itemId) async {
    final db = await _localDbService.database;

    await db.insert(
      'favourites',
      {
        'user_id': userId,
        'item_id': itemId,
        'is_deleted': 1,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markSynced(String userId, int itemId) async {
    final db = await _localDbService.database;

    await db.update(
      'favourites',
      {
        'is_synced': 1,
      },
      where: 'user_id = ? AND item_id = ?',
      whereArgs: [userId, itemId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsynced() async {
    final db = await _localDbService.database;

    return await db.query(
      'favourites',
      where: 'is_synced = 0',
      orderBy: 'updated_at ASC',
    );
  }
}
