import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
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
    final imageUrls = draft.imageUrls ?? <String>[];
    final remoteOrAssetImages = imageUrls
        .where((image) => image.startsWith('http') || image.startsWith('assets/'))
        .toList(growable: false);
    map['image_urls'] = jsonEncode(remoteOrAssetImages);
    map['updated_at'] = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.insert(
        'item_draft',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'item_draft_images',
        where: 'draft_id = ?',
        whereArgs: [draft.id],
      );

      var sortOrder = 0;
      for (final imagePath in imageUrls) {
        if (imagePath.startsWith('http') || imagePath.startsWith('assets/')) {
          continue;
        }

        final file = File(imagePath);
        if (!await file.exists()) {
          continue;
        }

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          continue;
        }

        await txn.insert('item_draft_images', {
          'draft_id': draft.id,
          'image_bytes': bytes,
          'image_ext': path.extension(imagePath).toLowerCase(),
          'sort_order': sortOrder,
        });
        sortOrder++;
      }
    });
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

    final draftId = (data['id'] as int?) ?? 1;
    final restoredLocalImagePaths = await _restoreDraftImagesFromDb(
      db: db,
      draftId: draftId,
    );
    final existingImageUrls = List<String>.from(data['image_urls'] as List<dynamic>);
    data['image_urls'] = <String>[
      ...existingImageUrls,
      ...restoredLocalImagePaths,
    ];

    return ItemDraft.fromMap(data);
  }

  Future<void> clearDraft() async {
    final db = await _localDbService.database;
    await db.transaction((txn) async {
      await txn.delete('item_draft_images', where: 'draft_id = ?', whereArgs: [1]);
      await txn.delete('item_draft', where: 'id = ?', whereArgs: [1]);
    });
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

  Future<List<String>> _restoreDraftImagesFromDb({
    required Database db,
    required int draftId,
  }) async {
    final rows = await db.query(
      'item_draft_images',
      columns: ['id', 'image_bytes', 'image_ext'],
      where: 'draft_id = ?',
      whereArgs: [draftId],
      orderBy: 'sort_order ASC, id ASC',
    );
    if (rows.isEmpty) {
      return const [];
    }

    final tempDir = await getTemporaryDirectory();
    final imagesDir = Directory(path.join(tempDir.path, 'swaply_draft_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final restoredPaths = <String>[];
    for (final row in rows) {
      final imageId = row['id'] as int?;
      final bytes = row['image_bytes'] as List<int>?;
      if (imageId == null || bytes == null || bytes.isEmpty) {
        continue;
      }

      final rawExt = (row['image_ext'] as String?)?.trim().toLowerCase() ?? '';
      final ext = rawExt.isEmpty ? '.jpg' : rawExt;
      final outputPath = path.join(imagesDir.path, 'draft_${draftId}_$imageId$ext');
      final file = File(outputPath);
      await file.writeAsBytes(bytes, flush: true);
      restoredPaths.add(outputPath);
    }

    return restoredPaths;
  }
}
