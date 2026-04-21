import 'dart:async';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../models/chat_message.dart';
import '../../services/local_db_service.dart';

class PendingOutgoingMessage {
  const PendingOutgoingMessage({
    required this.clientGeneratedId,
    required this.tempMessageId,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.retryCount,
    required this.failed,
  });

  final String clientGeneratedId;
  final int tempMessageId;
  final int chatId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final int retryCount;
  final bool failed;
}

class LocalMessagesRepository {
  LocalMessagesRepository({LocalDbService? localDbService})
    : _localDbService = localDbService ?? LocalDbService.instance;

  final LocalDbService _localDbService;
  final Random _random = Random();
  final Map<int, StreamController<List<ChatMessage>>> _controllers = {};

  Stream<List<ChatMessage>> watchForChat(int chatId) {
    final controller = _controllers.putIfAbsent(
      chatId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
    unawaited(_emit(chatId));
    return controller.stream;
  }

  Future<List<ChatMessage>> listForChat(int chatId) async {
    final db = await _localDbService.database;
    final rows = await db.query(
      'chat_messages_cache',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC, id ASC',
    );

    return rows
        .map(_fromLocalRow)
        .whereType<ChatMessage>()
        .toList(growable: false);
  }

  Future<PendingOutgoingMessage> insertPending({
    required int chatId,
    required String senderId,
    required String content,
  }) async {
    final now = DateTime.now().toUtc();
    final tempMessageId = -now.microsecondsSinceEpoch - _random.nextInt(1000);
    final clientGeneratedId =
        '${chatId}_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';

    final db = await _localDbService.database;
    await db.transaction((txn) async {
      await txn.insert('chat_messages_cache', {
        'id': tempMessageId,
        'client_generated_id': clientGeneratedId,
        'chat_id': chatId,
        'sender_id': senderId,
        'content': content,
        'read_at': null,
        'edited_at': null,
        'deleted_at': null,
        'deleted_by': null,
        'created_at': now.toIso8601String(),
        'is_synced': 0,
        'failed': 0,
        'last_synced_at': null,
        'sync_error': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.insert('pending_outgoing_messages', {
        'client_generated_id': clientGeneratedId,
        'temp_message_id': tempMessageId,
        'chat_id': chatId,
        'sender_id': senderId,
        'content': content,
        'created_at': now.toIso8601String(),
        'retry_count': 0,
        'failed': 0,
        'last_attempt_at': null,
        'last_error': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    await _emit(chatId);

    return PendingOutgoingMessage(
      clientGeneratedId: clientGeneratedId,
      tempMessageId: tempMessageId,
      chatId: chatId,
      senderId: senderId,
      content: content,
      createdAt: now,
      retryCount: 0,
      failed: false,
    );
  }

  Future<void> resolvePendingWithRemote({
    required PendingOutgoingMessage pending,
    required ChatMessage remote,
  }) async {
    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        'pending_outgoing_messages',
        where: 'client_generated_id = ?',
        whereArgs: [pending.clientGeneratedId],
      );
      await txn.delete(
        'chat_messages_cache',
        where: 'id = ? OR client_generated_id = ?',
        whereArgs: [pending.tempMessageId, pending.clientGeneratedId],
      );
      await txn.insert(
        'chat_messages_cache',
        _toRemoteLocalRow(
          remote,
          syncedAt: now,
          clientGeneratedId: pending.clientGeneratedId,
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    await _emit(pending.chatId);
  }

  Future<void> markPendingFailed({
    required PendingOutgoingMessage pending,
    required Object error,
  }) async {
    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final errorText = error.toString();

    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''
          UPDATE pending_outgoing_messages
          SET retry_count = retry_count + 1,
              failed = 1,
              last_attempt_at = ?,
              last_error = ?
          WHERE client_generated_id = ?
        ''',
        [now, errorText, pending.clientGeneratedId],
      );
      await txn.update(
        'chat_messages_cache',
        {
          'is_synced': 0,
          'failed': 1,
          'last_synced_at': now,
          'sync_error': errorText,
        },
        where: 'id = ? OR client_generated_id = ?',
        whereArgs: [pending.tempMessageId, pending.clientGeneratedId],
      );
    });

    await _emit(pending.chatId);
  }

  Future<void> upsertRemoteMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) {
      return;
    }

    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final message in messages) {
        batch.insert(
          'chat_messages_cache',
          _toRemoteLocalRow(message, syncedAt: now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });

    await _emit(messages.first.chatId);
  }

  Future<void> updateCachedMediaPath({
    required int messageId,
    required String cachedPath,
  }) async {
    final db = await _localDbService.database;
    await db.update(
      'chat_messages_cache',
      {'cached_media_path': cachedPath},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> markChatReadLocally({
    required int chatId,
    required String viewerId,
  }) async {
    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'chat_messages_cache',
      {'read_at': now, 'is_synced': 1, 'failed': 0, 'last_synced_at': now},
      where: 'chat_id = ? AND sender_id != ? AND read_at IS NULL',
      whereArgs: [chatId, viewerId],
    );
    await _emit(chatId);
  }

  Future<void> markMessageEditedLocally({
    required int messageId,
    required String content,
  }) async {
    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      'chat_messages_cache',
      columns: ['chat_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    await db.update(
      'chat_messages_cache',
      {
        'content': content,
        'edited_at': now,
        'is_synced': 1,
        'failed': 0,
        'last_synced_at': now,
        'sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    if (rows.isNotEmpty) {
      final chatId = rows.first['chat_id'] as int?;
      if (chatId != null) {
        await _emit(chatId);
      }
    }
  }

  Future<void> markMessageDeletedLocally({
    required int messageId,
    required String actorId,
  }) async {
    final db = await _localDbService.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      'chat_messages_cache',
      columns: ['chat_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    await db.update(
      'chat_messages_cache',
      {
        'deleted_at': now,
        'deleted_by': actorId,
        'is_synced': 1,
        'failed': 0,
        'last_synced_at': now,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    if (rows.isNotEmpty) {
      final chatId = rows.first['chat_id'] as int?;
      if (chatId != null) {
        await _emit(chatId);
      }
    }
  }

  Future<List<PendingOutgoingMessage>> listPendingByChat(int chatId) async {
    final db = await _localDbService.database;
    final rows = await db.query(
      'pending_outgoing_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );

    return rows
        .map((row) {
          return PendingOutgoingMessage(
            clientGeneratedId: row['client_generated_id'] as String,
            tempMessageId: row['temp_message_id'] as int,
            chatId: row['chat_id'] as int,
            senderId: row['sender_id'] as String,
            content: row['content'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
            retryCount: (row['retry_count'] as int?) ?? 0,
            failed: ((row['failed'] as int?) ?? 0) == 1,
          );
        })
        .toList(growable: false);
  }

  Future<void> publishChat(int chatId) async {
    await _emit(chatId);
  }

  Map<String, dynamic> _toRemoteLocalRow(
    ChatMessage message, {
    required String syncedAt,
    String? clientGeneratedId,
    String? cachedMediaPath,
  }) {
    return {
      'id': message.id,
      'client_generated_id': clientGeneratedId,
      'chat_id': message.chatId,
      'sender_id': message.senderId,
      'content': message.content,
      'cached_media_path': cachedMediaPath,
      'read_at': message.readAt?.toUtc().toIso8601String(),
      'edited_at': message.editedAt?.toUtc().toIso8601String(),
      'deleted_at': message.deletedAt?.toUtc().toIso8601String(),
      'deleted_by': message.deletedBy,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'is_synced': 1,
      'failed': 0,
      'last_synced_at': syncedAt,
      'sync_error': null,
    };
  }

  ChatMessage? _fromLocalRow(Map<String, Object?> row) {
    final map = <String, dynamic>{
      'id': row['id'],
      'chat_id': row['chat_id'],
      'sender_id': row['sender_id'],
      'content': row['content'],
      'read_at': row['read_at'],
      'edited_at': row['edited_at'],
      'deleted_at': row['deleted_at'],
      'deleted_by': row['deleted_by'],
      'created_at': row['created_at'],
    };

    try {
      return ChatMessage.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _emit(int chatId) async {
    final controller = _controllers[chatId];
    if (controller == null || controller.isClosed) {
      return;
    }

    final messages = await listForChat(chatId);
    controller.add(messages);
  }
}
