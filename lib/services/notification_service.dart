import 'dart:async';
import 'dart:convert';

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
  static const String _selectColumns =
      'id,title,body,created_at,is_read,type,data';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<List<SystemNotificationItem>> _streamController =
      StreamController<List<SystemNotificationItem>>.broadcast();
    final StreamController<Map<String, dynamic>> _tapStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _notificationsChannel;
  String? _subscribedRecipientId;
  bool _isChatTabActive = false;
    Map<String, dynamic>? _pendingTapPayload;

  bool _isInitialized = false;

  Stream<List<SystemNotificationItem>> get notificationsStream =>
      _streamController.stream;

  Stream<Map<String, dynamic>> get notificationTapStream =>
      _tapStreamController.stream;

  Map<String, dynamic>? takePendingNotificationTap() {
    final payload = _pendingTapPayload;
    _pendingTapPayload = null;
    return payload;
  }

  void setChatTabActive(bool isActive) {
    _isChatTabActive = isActive;
  }

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
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTapPayload(response.payload);
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _handleNotificationTapPayload(launchDetails?.notificationResponse?.payload);
    }

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
    _bindRealtimeNotifications();
    _isInitialized = true;
  }

  void _bindRealtimeNotifications() {
    if (!SupabaseService.isConfigured) {
      return;
    }

    _authSubscription ??= SupabaseService.client.auth.onAuthStateChange.listen((_) {
      unawaited(_restartRealtimeSubscription());
    });

    unawaited(_restartRealtimeSubscription());
  }

  Future<void> _restartRealtimeSubscription() async {
    final recipientId = SupabaseService.client.auth.currentUser?.id;
    if (_subscribedRecipientId == recipientId && _notificationsChannel != null) {
      return;
    }

    await _removeRealtimeSubscription();
    _subscribedRecipientId = recipientId;

    if (recipientId == null) {
      _streamController.add(const []);
      return;
    }

    final channel = SupabaseService.client.channel(
      'notifications:$recipientId',
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: _table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: recipientId,
      ),
      callback: (payload) {
        unawaited(_handleIncomingNotification(payload.newRecord));
      },
    );

    await channel.subscribe();
    _notificationsChannel = channel;
    await _emitLatest();
  }

  Future<void> _removeRealtimeSubscription() async {
    final channel = _notificationsChannel;
    _notificationsChannel = null;
    if (channel != null) {
      await SupabaseService.client.removeChannel(channel);
    }
  }

  Future<void> _handleIncomingNotification(dynamic rawRow) async {
    final row = _normalizeMap(rawRow);
    final title = row['title']?.toString().trim() ?? '';
    final body = row['body']?.toString().trim() ?? '';
    final type = row['type']?.toString().trim().toLowerCase() ?? '';

    final shouldSuppressLocal = type == 'chat' && _isChatTabActive;

    if (!shouldSuppressLocal && (title.isNotEmpty || body.isNotEmpty)) {
      await _showLocalNotification(
        title: title.isEmpty ? 'Swaply' : title,
        body: body,
        payload: _buildNotificationPayload(
          notificationId: row['id']?.toString(),
          type: type,
          data: _normalizeMap(row['data']),
        ),
      );
    }

    await _emitLatest();
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
    String? payload,
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
      payload: payload,
    );
  }

  void _handleNotificationTapPayload(String? rawPayload) {
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return;
    }

    final decoded = _decodePayload(rawPayload);
    if (decoded == null) {
      return;
    }

    if (_tapStreamController.hasListener) {
      _tapStreamController.add(decoded);
      return;
    }

    _pendingTapPayload = decoded;
  }

  String _buildNotificationPayload({
    required String type,
    required Map<String, dynamic> data,
    String? notificationId,
  }) {
    return jsonEncode({
      if (notificationId != null && notificationId.isNotEmpty)
        'notification_id': notificationId,
      'type': type,
      'data': data,
    });
  }

  Map<String, dynamic>? _decodePayload(String rawPayload) {
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
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

  Map<String, dynamic> _normalizeMap(dynamic row) {
    if (row is Map<String, dynamic>) {
      return row;
    }
    if (row is Map) {
      return row.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }
}
