import 'package:sqflite/sqflite.dart';

import '../../services/local_db_service.dart';

class LocalSearchHistoryRepository {
  LocalSearchHistoryRepository({LocalDbService? localDbService})
    : _localDbService = localDbService ?? LocalDbService.instance;

  static const int _maxEntries = 5;
  final LocalDbService _localDbService;

  Future<void> saveQuery(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }

    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('search_history', {
      'query': normalized,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.update(
      'search_history',
      {'updated_at': now},
      where: 'query = ?',
      whereArgs: [normalized],
    );

    await db.rawDelete(
      '''
      DELETE FROM search_history
      WHERE id NOT IN (
        SELECT id FROM search_history
        ORDER BY updated_at DESC
        LIMIT ?
      )
      ''',
      [_maxEntries],
    );
  }

  Future<List<String>> listRecent() async {
    final db = await _localDbService.database;
    final rows = await db.query(
      'search_history',
      columns: ['query'],
      orderBy: 'updated_at DESC',
      limit: _maxEntries,
    );
    return rows
        .map((row) => (row['query'] as String?)?.trim() ?? '')
        .where((query) => query.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> clear() async {
    final db = await _localDbService.database;
    await db.delete('search_history');
  }
}
