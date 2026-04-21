import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:swaply/models/item_draft.dart';
import '../../services/local_db_service.dart';

class LocalDraftRepository {
  LocalDraftRepository({LocalDbService? localDbService})
      : _localDbService = localDbService ?? LocalDbService.instance;

  final LocalDbService _localDbService;

  Future<void> upsertDraft(ItemDraft draft) async {
    final db = await _localDbService.database;
    final map = draft.toMap();
    map['image_urls'] = jsonEncode(draft.imageUrls ?? <String>[]);
    map['updated_at'] = DateTime.now().toIso8601String();

    await db.insert(
      'item_draft',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ItemDraft?> getDraft() async {
    final db = await _localDbService.database;

    final result = await db.query(
      'item_draft',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (result.isEmpty) return null;

    final data = Map<String, dynamic>.from(result.first);
    final rawImages = data['image_urls'];
    if (rawImages is String && rawImages.isNotEmpty) {
      data['image_urls'] = List<String>.from(jsonDecode(rawImages) as List);
    } else if (rawImages == null) {
      data['image_urls'] = <String>[];
    }

    return ItemDraft.fromMap(data);
  }

  Future<void> clearDraft() async {
    final db = await _localDbService.database;
    await db.delete('item_draft', where: 'id = ?', whereArgs: [1]);
  }

  Future<void> markAsPendingUpload() async {
    final db = await _localDbService.database;

    await db.update(
      'item_draft',
      {
        'is_pending_upload': 1,
      },
      where: 'id = ?',
      whereArgs: [1],
    );
  }
}
