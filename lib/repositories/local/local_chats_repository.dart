import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/chat_thread.dart';
import '../../services/local_db_service.dart';

class LocalChatsRepository {
  LocalChatsRepository({LocalDbService? localDbService})
    : _localDbService = localDbService ?? LocalDbService.instance;

  final LocalDbService _localDbService;

  Future<List<ChatThread>> listForUser(String userId) async {
    final db = await _localDbService.database;
    final rows = await db.query(
      'chat_threads_cache',
      where: 'user1_id = ? OR user2_id = ?',
      whereArgs: [userId, userId],
      orderBy: 'updated_at DESC',
    );

    return rows
        .map(_fromLocalRow)
        .whereType<ChatThread>()
        .toList(growable: false);
  }

  Future<ChatThread?> getById(int chatId) async {
    final db = await _localDbService.database;
    final rows = await db.query(
      'chat_threads_cache',
      where: 'id = ?',
      whereArgs: [chatId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromLocalRow(rows.first);
  }

  Future<void> upsertMany(List<ChatThread> threads) async {
    if (threads.isEmpty) {
      return;
    }

    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final thread in threads) {
        batch.insert(
          'chat_threads_cache',
          _toLocalRow(thread, syncedAt: now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertOne(ChatThread thread) async {
    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'chat_threads_cache',
      _toLocalRow(thread, syncedAt: now),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateLastMessage({
    required int chatId,
    required String messagePreview,
  }) async {
    final db = await _localDbService.database;
    await db.update(
      'chat_threads_cache',
      {
        'last_message': messagePreview,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'is_synced': 1,
        'failed': 0,
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  Map<String, dynamic> _toLocalRow(
    ChatThread thread, {
    required String syncedAt,
  }) {
    return {
      'id': thread.id,
      'user1_id': thread.user1Id,
      'user2_id': thread.user2Id,
      'user1_name': thread.user1Name,
      'user2_name': thread.user2Name,
      'user1_profile_image': thread.user1ProfileImage,
      'user2_profile_image': thread.user2ProfileImage,
      'item_id': thread.itemId,
      'item_title': thread.itemTitle,
      'item_owner_id': thread.itemOwnerId,
      'item_image_urls': jsonEncode(thread.itemImageUrls),
      'last_message': thread.lastMessage,
      'pinned_message_id': thread.pinnedMessageId,
      'pinned_at': thread.pinnedAt?.toUtc().toIso8601String(),
      'updated_at': thread.updatedAt.toUtc().toIso8601String(),
      'is_synced': 1,
      'failed': 0,
      'last_synced_at': syncedAt,
    };
  }

  ChatThread? _fromLocalRow(Map<String, Object?> row) {
    List<String> itemImageUrls = const [];
    final rawItemImageUrls = row['item_image_urls'];
    if (rawItemImageUrls is String && rawItemImageUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawItemImageUrls);
        if (decoded is List) {
          itemImageUrls = decoded
              .where((value) => value != null)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
    }

    final map = <String, dynamic>{
      'id': row['id'],
      'user1_id': row['user1_id'],
      'user2_id': row['user2_id'],
      'item_id': row['item_id'],
      'last_message': row['last_message'],
      'pinned_message_id': row['pinned_message_id'],
      'pinned_at': row['pinned_at'],
      'updated_at': row['updated_at'],
      'user1': {
        'id': row['user1_id'],
        'username': row['user1_name'],
        'profile_image': row['user1_profile_image'],
      },
      'user2': {
        'id': row['user2_id'],
        'username': row['user2_name'],
        'profile_image': row['user2_profile_image'],
      },
      'item': {
        'owner_id': row['item_owner_id'],
        'name': row['item_title'],
        'image_urls': itemImageUrls,
      },
    };

    try {
      return ChatThread.fromMap(map);
    } catch (_) {
      return null;
    }
  }
}
