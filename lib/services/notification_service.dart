import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/system_notification_item.dart';
import 'supabase_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _table = 'notifications';
  static const String _channelId = 'swaply_general_channel';
  static const String _channelName = 'Swaply Notifications';
  static const String _channelDescription =
      'General system notifications for Swaply';
  static const String _androidNotificationIcon = 'ic_stat_notify';
  static const String _selectColumns = 'id,title,body,created_at,is_read,type';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<List<SystemNotificationItem>> _streamController =
      StreamController<List<SystemNotificationItem>>.broadcast();

  bool _isInitialized = false;

  Stream<List<SystemNotificationItem>> get notificationsStream =>
      _streamController.stream;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      _androidNotificationIcon,
    );
    const iosSettings = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    await requestPermission();
    _isInitialized = true;
  }

  Future<void> requestPermission() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    final macPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macPlugin?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> sendSystemNotification({
    required String title,
    required String body,
    String type = 'general',
    String? recipientId,
    String? actorId,
    Map<String, dynamic>? data,
    bool showLocal = true,
  }) async {
    await initialize();

    if (!SupabaseService.isConfigured) {
      if (showLocal) {
        await _showLocalNotification(title: title, body: body);
      }
      return;
    }

    final currentUserId = SupabaseService.client.auth.currentUser?.id;
    final targetRecipientId = recipientId ?? currentUserId;
    if (targetRecipientId == null) {
      throw StateError('No authenticated user found for notification insert.');
    }

    await SupabaseService.client.from(_table).insert({
      'recipient_id': targetRecipientId,
      'actor_id': actorId ?? currentUserId,
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? const <String, dynamic>{},
    });

    await _emitLatest();

    if (showLocal) {
      await _showLocalNotification(title: title, body: body);
    }
  }

  Future<void> sendNotificationToUser({
    required String recipientId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
    bool showLocal = false,
  }) async {
    final actorId = _requireCurrentUserId();
    await sendSystemNotification(
      title: title,
      body: body,
      type: type,
      recipientId: recipientId,
      actorId: actorId,
      data: data,
      showLocal: showLocal,
    );
  }

  Future<List<SystemNotificationItem>> getNotifications({
    int limit = 100,
  }) async {
    if (!SupabaseService.isConfigured) {
      return const [];
    }

    final userId = _requireCurrentUserId();
    final response = await SupabaseService.client
        .from(_table)
        .select(_selectColumns)
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    final rows = _ensureListOfMaps(response, operation: 'getNotifications');
    return rows
        .map<SystemNotificationItem>(SystemNotificationItem.fromMap)
        .toList(growable: false);
  }

  Future<void> markAsRead(String id) async {
    if (!SupabaseService.isConfigured) {
      return;
    }

    final userId = _requireCurrentUserId();
    await SupabaseService.client
        .from(_table)
        .update({'is_read': true})
        .eq('id', id)
        .eq('recipient_id', userId);

    await _emitLatest();
  }

  Future<void> markAllAsRead() async {
    if (!SupabaseService.isConfigured) {
      return;
    }

    final userId = _requireCurrentUserId();
    await SupabaseService.client
        .from(_table)
        .update({'is_read': true})
        .eq('recipient_id', userId)
        .eq('is_read', false);

    await _emitLatest();
  }

  Future<void> clearAll() async {
    if (!SupabaseService.isConfigured) {
      _streamController.add(const []);
      return;
    }

    final userId = _requireCurrentUserId();
    await SupabaseService.client
        .from(_table)
        .delete()
        .eq('recipient_id', userId);

    _streamController.add(const []);
  }

  Future<int> unreadCount() async {
    if (!SupabaseService.isConfigured) {
      return 0;
    }

    final userId = _requireCurrentUserId();
    final response = await SupabaseService.client
        .from(_table)
        .select('id')
        .eq('recipient_id', userId)
        .eq('is_read', false)
        .count(CountOption.exact);
    return response.count;
  }

  Future<void> refresh() async {
    await _emitLatest();
  }

  Future<void> _emitLatest() async {
    try {
      final items = await getNotifications();
      _streamController.add(items);
    } catch (_) {}
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _plugin.show(
      notificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  String _requireCurrentUserId() {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError(
        'No authenticated user found for notification operation.',
      );
    }
    return userId;
  }

  List<Map<String, dynamic>> _ensureListOfMaps(
    dynamic response, {
    required String operation,
  }) {
    if (response is! List) {
      throw StateError('Unexpected $operation response: expected List.');
    }

    return response
        .map<Map<String, dynamic>>((row) {
          if (row is Map<String, dynamic>) {
            return row;
          }
          if (row is Map) {
            return row.map((key, value) => MapEntry(key.toString(), value));
          }
          throw StateError('Unexpected $operation row shape: expected Map.');
        })
        .toList(growable: false);
  }
}
