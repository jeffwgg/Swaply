import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/app_snack_bars.dart';
import '../../../models/app_user.dart';
import '../../../models/system_notification_item.dart';
import '../../../repositories/items_repository.dart';
import '../../../repositories/users_repository.dart';
import '../../../services/notification_service.dart';
import '../../../services/supabase_service.dart';
import '../item/item_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService.instance;
  final ItemsRepository _itemsRepository = ItemsRepository();
  final UsersRepository _usersRepository = UsersRepository();

  List<SystemNotificationItem> _items = const [];
  bool _isLoading = true;
  AppUser? _currentUser;
  StreamSubscription<List<SystemNotificationItem>>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadItems();
    _subscription = _notificationService.notificationsStream.listen((items) {
      if (!mounted) {
        return;
      }
      setState(() => _items = items);
    });
  }

  Future<void> _loadCurrentUser() async {
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser == null) {
      return;
    }
    final user = await _usersRepository.getById(authUser.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _currentUser = user;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadItems() async {
    List<SystemNotificationItem> items = const [];
    try {
      items = await _notificationService.getNotifications();
    } catch (_) {
      items = const [];
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _markAllAsRead() async {
    await _notificationService.markAllAsRead();
  }

  Future<void> _clearAll() async {
    await _notificationService.clearAll();
  }

  Future<void> _markAsRead(SystemNotificationItem item) async {
    if (item.isRead) {
      return;
    }
    await _notificationService.markAsRead(item.id);
  }

  Future<void> _onNotificationTap(SystemNotificationItem item) async {
    await _markAsRead(item);

    final itemId = item.itemId;
    if (itemId == null || !mounted) {
      return;
    }

    try {
      final listing = await _itemsRepository.getById(itemId);
      if (!mounted || listing == null) {
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ItemDetailsScreen(loginUser: _currentUser, item: listing),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBars.error(context, 'Unable to open the related item.');
    }
  }

  String _formatTimestamp(DateTime date) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'trade':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9F7FF), Color(0xFFEFE9FF)],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? const _EmptyNotificationsState()
            : RefreshIndicator(
                onRefresh: _loadItems,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return InkWell(
                      onTap: () => _onNotificationTap(item),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: item.isRead
                              ? Colors.white.withValues(alpha: 0.85)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: item.isRead
                                ? const Color(0xFFE6E2F7)
                                : const Color(0xFFCDBDFF),
                            width: 1.3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF7A54FF,
                              ).withValues(alpha: 0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFB792FF),
                                    Color(0xFF7A54FF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _iconForType(item.type),
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: TextStyle(
                                            color: const Color(0xFF1F1A39),
                                            fontSize: 15,
                                            fontWeight: item.isRead
                                                ? FontWeight.w600
                                                : FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (!item.isRead)
                                        Container(
                                          width: 9,
                                          height: 9,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF7A54FF),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.body,
                                    style: const TextStyle(
                                      color: Color(0xFF615A81),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _formatTimestamp(item.createdAt),
                                    style: const TextStyle(
                                      color: Color(0xFF9A93BB),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemCount: _items.length,
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF6F45FF),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await _notificationService.sendSystemNotification(
              title: 'Swaply Notification Test',
              body: 'This confirms your system notifications are working.',
              type: 'general',
            );
          } catch (e) {
            if (!mounted) return;
            AppSnackBars.error(context, 'Unable to send notification: $e');
          }
        },
        icon: const Icon(
          Icons.notifications_active_rounded,
          color: Colors.white,
        ),
        label: const Text('Test Notify', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.notifications_off_rounded,
              size: 62,
              color: Color(0xFF9D90CB),
            ),
            SizedBox(height: 14),
            Text(
              'No notifications yet',
              style: TextStyle(
                color: Color(0xFF312B51),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'System notifications you trigger from actions will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6D6691),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
