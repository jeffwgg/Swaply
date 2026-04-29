import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:swaply/core/utils/app_snack_bars.dart';
import 'package:swaply/models/app_user.dart';
import 'package:swaply/models/item_listing.dart';
import 'package:swaply/models/payment.dart';
import 'package:swaply/models/transaction.dart';
import 'package:swaply/repositories/items_repository.dart';
import 'package:swaply/repositories/local/local_transactions_repository.dart';
import 'package:swaply/repositories/payments_repository.dart';
import 'package:swaply/repositories/transactions_repository.dart';
import 'package:swaply/repositories/users_repository.dart';
import 'package:swaply/repositories/local/local_profile_items_repository.dart';
import 'package:swaply/services/network_service.dart';
import 'package:swaply/models/checkout_flow_kind.dart';
import 'package:swaply/models/meetup_address_option.dart';
import 'package:swaply/views/screens/item/item_detail_screen.dart';
import 'package:swaply/views/screens/profile/profile_screen.dart';
import 'package:swaply/views/screens/transaction/transaction_detail_screen.dart';
import 'package:swaply/views/screens/transaction/checkout_screen.dart';
import 'package:swaply/views/screens/transaction/qr_scan_screen.dart';
import 'package:swaply/services/supabase_service.dart';
import 'package:swaply/repositories/favourite_repository.dart' hide debugPrint;

class ProfileTabs extends StatefulWidget {
  final String userId;
  final bool isOwnProfile;

  const ProfileTabs({super.key, required this.userId,this.isOwnProfile = false,});

  @override
  State<ProfileTabs> createState() => _ProfileTabsState();
}

class _ProfileTabsState extends State<ProfileTabs> {
  AppUser? user;
  AppUser? currentUser;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await UsersRepository().getById(widget.userId);
    final authUser = SupabaseService.client.auth.currentUser;
    AppUser? cu;
    if (authUser != null) {
      cu = await UsersRepository().getById(authUser.id);
    }
    if (mounted) {
      setState(() {
        this.user = user;
        this.currentUser = cu;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
      );
    }

    if (!widget.isOwnProfile) {
      return DefaultTabController(
        length: 1,
        child: Column(
          children: [
            const TabBar(
              isScrollable: false,
              tabAlignment: TabAlignment.fill,
              labelColor: Color(0xFF5B21B6),
              unselectedLabelColor: Colors.grey,
              indicatorColor: Color(0xFF5B21B6),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 3,
              tabs: [
                Tab(text: "Listing"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ItemTab(
                    loginUser: currentUser!,
                    profileUser: user!,
                    isOwnProfile: widget.isOwnProfile, // ← 加这行
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            labelColor: Color(0xFF5B21B6),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFF5B21B6),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 3,
            tabs: [
              Tab(text: "Favourite"),
              Tab(text: "Your Item"),
              Tab(text: "Transaction"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                FavouriteTab(user: user!),
                ItemTab(loginUser: currentUser!, profileUser: currentUser!),
                TransactionTab(user: user!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionTab extends StatefulWidget {
  final AppUser user;
  const TransactionTab({super.key, required this.user});

  @override
  State<TransactionTab> createState() => _TransactionTabState();
}

class _TransactionTabState extends State<TransactionTab> {
  late Future<List<_TransactionRow>> _future;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    _future = _loadRows();
  }

  void _triggerReload() {
    if (!mounted) return;
    setState(() {
      _future = _loadRows();
    });
  }

  Future<void> _reload() async {
    if (_reloading) return;
    _reloading = true;
    try {
      final future = _loadRows();
      if (!mounted) return;
      setState(() {
        _future = future;
      });
      await future;
      if (!mounted) return;
      setState(() {});
    } finally {
      _reloading = false;
    }
  }

  Future<List<_TransactionRow>> _loadRows() async {
    final repo = TransactionsRepository();
    final paymentsRepo = PaymentsRepository();
    final itemsRepo = ItemsRepository();
    final usersRepo = UsersRepository();
    final localRepo = LocalTransactionsRepository();

    List<Transaction> all = const [];
    try {
      final buyerTxs = await repo.listForBuyer(widget.user.id);
      final sellerTxs = await repo.listForSeller(widget.user.id);
      all = <Transaction>[...buyerTxs, ...sellerTxs];
    } catch (_) {
      // Offline or request failed -> load from local cache.
      final cached = await localRepo.listForUser(widget.user.id);
      return cached
          .map(
            (c) => _TransactionRow(
              tx: c.tx,
              item: c.itemImageUrl == null
                  ? null
                  : ItemListing(
                      id: c.tx.itemId,
                      name: c.itemName ?? 'Item #${c.tx.itemId}',
                      description: '',
                      price: c.tx.itemPrice,
                      listingType: 'sell',
                      ownerId: c.tx.sellerId,
                      status: c.itemStatus ?? 'unknown',
                      category: c.itemCategory ?? '',
                      imageUrls: c.itemImageUrl == null ? [] : [c.itemImageUrl!],
                      preference: null,
                      repliedTo: null,
                      createdAt: c.tx.createdAt,
                      address: null,
                      latitude: null,
                      longitude: null,
                    ),
              tradedItem: c.tradedItemImageUrl == null && c.tx.tradedItemId == null
                  ? null
                  : ItemListing(
                      id: c.tx.tradedItemId ?? 0,
                      name: c.tradedItemName ?? 'Item #${c.tx.tradedItemId}',
                      description: '',
                      price: null,
                      listingType: 'trade',
                      ownerId: c.tx.buyerId,
                      status: c.tradedItemStatus ?? 'unknown',
                      category: c.tradedItemCategory ?? '',
                      imageUrls: c.tradedItemImageUrl == null
                          ? []
                          : [c.tradedItemImageUrl!],
                      preference: null,
                      repliedTo: null,
                      createdAt: c.tx.createdAt,
                      address: null,
                      latitude: null,
                      longitude: null,
                    ),
              payment: null,
              seller: c.sellerUsername == null
                  ? null
                  : AppUser(
                      id: c.tx.sellerId,
                      username: c.sellerUsername!,
                      email: '',
                      profileImage: null,
                      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
                    ),
            ),
          )
          .toList();
    }

    // Deduplicate by transactionId (in case policies allow seeing both views).
    final byId = <int, Transaction>{};
    for (final t in all) {
      byId[t.transactionId] = t;
    }

    final unique = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final rows = <_TransactionRow>[];
    for (final tx in unique) {
      final item = await itemsRepo.getById(tx.itemId);
      final tradedItem = tx.tradedItemId == null
          ? null
          : await itemsRepo.getById(tx.tradedItemId!);
      final payments = await paymentsRepo.listForTransaction(tx.transactionId);
      final latestPayment = payments.isNotEmpty ? payments.first : null;
      final seller = await usersRepo.getById(tx.sellerId);

      // Write-through cache for offline history.
      await localRepo.upsertFromRemote(
        tx: tx,
        sellerUsername: seller?.username,
        itemName: item?.name,
        itemImageUrl:
            (item != null && item.imageUrls.isNotEmpty) ? item.imageUrls.first : null,
        itemCategory: item?.category,
        itemStatus: item?.status,
        tradedItemName: tradedItem?.name,
        tradedItemImageUrl: (tradedItem != null && tradedItem.imageUrls.isNotEmpty)
            ? tradedItem.imageUrls.first
            : null,
        tradedItemCategory: tradedItem?.category,
        tradedItemStatus: tradedItem?.status,
      );

      rows.add(
        _TransactionRow(
          tx: tx,
          item: item,
          tradedItem: tradedItem,
          payment: latestPayment,
          seller: seller,
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_TransactionRow>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return _buildEmptyState(Icons.receipt_long_outlined, "No transactions yet");
        }

        return SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
            final row = rows[i];
            final tx = row.tx;
            final item = row.item;
            final title = item?.name ?? 'Item #${tx.itemId}';
            final sellerName = row.seller?.username ?? 'Seller';
            final isBuyer = tx.buyerId == widget.user.id;

            final amount = tx.totalAmount ?? tx.itemPrice ?? 0;
            final amountLabel = amount > 0 ? 'RM ${amount.toStringAsFixed(2)}' : 'RM 0.00';

            final status = tx.transactionStatus ?? 'unknown';
            final dateLabel = DateFormat('MMM d, yyyy • hh:mm a').format(tx.createdAt.toLocal());
            final isTrade = tx.tradedItemId != null;
            final isMeetupPurchase =
                !isTrade && (tx.fulfillmentMethod ?? '').toLowerCase() == 'meetup';

            Future<void> onScanMeetupPurchaseQr() async {
              final raw = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => const QrScanScreen(title: 'Scan meet-up QR'),
                ),
              );
              if (!context.mounted || raw == null || raw.trim().isEmpty) return;

              final parsed = TradeQrPayload.tryParse(raw.trim());
              if (parsed == null) {
                AppSnackBars.error(context, 'Invalid QR code.');
                return;
              }

              // Purchase meetup: only buyer scans seller QR.
              if (parsed.transactionId != tx.transactionId ||
                  parsed.role != 'seller' ||
                  parsed.uid != tx.sellerId) {
                AppSnackBars.error(context, 'This QR does not match the seller.');
                return;
              }

              try {
                await ItemsRepository().updateStatus('completed', tx.itemId);
                await TransactionsRepository().updateStatus(
                  transactionId: tx.transactionId,
                  transactionStatus: 'completed',
                );
                AppSnackBars.success(context, 'Marked as received.');
                await _reload();
              } catch (e) {
                AppSnackBars.error(context, 'Failed to mark received: $e');
              }
            }

            Future<void> onGenerateMeetupPurchaseQr() async {
              final payload = TradeQrPayload(
                transactionId: tx.transactionId,
                role: 'seller',
                uid: widget.user.id,
              );
              final raw = jsonEncode(payload.toJson());

              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                backgroundColor: Colors.white,
                builder: (ctx) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Your meet-up QR',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE9D5FF)),
                            color: const Color(0xFFF8F5FF),
                          ),
                          child: QrImageView(
                            data: raw,
                            size: 240,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Let the buyer scan this QR.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Close'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            }

            Future<void> onReceived() async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Confirm received'),
                  content: const Text(
                    'Confirm you have received the product? This will complete the transaction.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Back'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await ItemsRepository().updateStatus('completed', tx.itemId);
                await TransactionsRepository().updateStatus(
                  transactionId: tx.transactionId,
                  transactionStatus: 'completed',
                );
                if (!context.mounted) return;
                AppSnackBars.success(context, 'Marked as received.');
                _reload();
              } catch (e) {
                if (!context.mounted) return;
                AppSnackBars.error(context, 'Failed to mark received: $e');
              }
            }

            Future<void> onProceed() async {
              try {
                final latestPrimary =
                    item ?? await ItemsRepository().getById(tx.itemId);
                if (latestPrimary == null) {
                  throw StateError('Item not found.');
                }
                final latestOffered = row.tradedItem ??
                    (tx.tradedItemId == null
                        ? null
                        : await ItemsRepository().getById(tx.tradedItemId!));
                if (latestOffered == null) {
                  throw StateError('Offered item not found.');
                }
                final seller =
                    row.seller ?? await UsersRepository().getById(tx.sellerId);
                final meetups = MeetupAddressOption.fromTradeItems(
                  sellerItem: latestPrimary,
                  offeredItem: latestOffered,
                );

                if (!context.mounted) return;
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckoutScreen(
                      flowKind: CheckoutFlowKind.swap,
                      primaryItem: latestPrimary,
                      swapItem: latestOffered,
                      sellerDisplayName: seller?.username ?? 'Seller',
                      sellerId: tx.sellerId,
                      buyerId: tx.buyerId,
                      sellerMeetupOptions: meetups,
                      // trade: meet-up only, no payment
                      tradeTransactionId: tx.transactionId,
                      meetUpOnly: true,
                      hidePaymentSection: true,
                    ),
                  ),
                );
                if (!context.mounted) return;
                await _reload();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Proceed failed: $e')),
                );
              }
            }

            Future<void> onCancel() async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cancel transaction'),
                  content: const Text('Cancel this transaction?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Back'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Cancel transaction'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await ItemsRepository().updateStatus('available', tx.itemId);
                if (tx.tradedItemId != null) {
                  // Offerer (buyer) cancel => drop offered item.
                  // Seller cancel => make offered item available again.
                  await ItemsRepository().updateStatus(
                    isBuyer ? 'dropped' : 'rejected',
                    tx.tradedItemId!,
                  );
                }
                await TransactionsRepository().updateStatus(
                  transactionId: tx.transactionId,
                  transactionStatus: 'cancelled',
                  cancelledBy: isBuyer ? 'buyer' : 'seller',
                );
                // Only attempt refund when there is a payment record (non-trade purchase).
                // And only the buyer should trigger the refund (RLS usually restricts this).
                if (!isTrade && row.payment != null && isBuyer) {
                  await PaymentsRepository().updateStatusForTransaction(
                    transactionId: tx.transactionId,
                    paymentStatus: 'refunded',
                  );
                }
                if (!context.mounted) return;
                AppSnackBars.info(
                  context,
                  (!isTrade && row.payment != null && isBuyer)
                      ? 'Cancelled. Refund will be issued in 3 working days.'
                      : 'Cancelled.',
                );
                await _reload();
              } catch (e) {
                debugPrint('[TransactionTab onCancel] Failed for tx=${tx.transactionId}: $e');
                if (!context.mounted) return;
                AppSnackBars.error(context, 'Failed to cancel: $e');
              }
            }

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE9D5FF)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransactionDetailScreen(
                        viewer: widget.user,
                        tx: tx,
                        item: item,
                        tradedItem: row.tradedItem,
                        seller: row.seller,
                        payment: row.payment,
                        isBuyer: isBuyer,
                        onChanged: _triggerReload,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _TxnThumb(url: item?.imageUrls.isNotEmpty == true ? item!.imageUrls.first : null),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () {
                                    if (row.seller == null) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProfileScreen(
                                          viewingUserId: row.seller!.id,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    sellerName,
                                    style: const TextStyle(
                                      color: Color(0xFF7C3AED),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(dateLabel, style: const TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                amountLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF5B21B6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              _StatusBadge(status: status, mini: true),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (status == 'pending')
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: onCancel,
                                child: const Text('Cancel'),
                              ),
                            ),
                            if (!isBuyer && !isTrade && isMeetupPurchase) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: onGenerateMeetupPurchaseQr,
                                  child: const Text('Generate QR Code'),
                                ),
                              ),
                            ],
                            if (isBuyer && !isTrade && isMeetupPurchase) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: onScanMeetupPurchaseQr,
                                  child: const Text('Scan QR'),
                                ),
                              ),
                            ],
                            if (isBuyer && !isTrade && !isMeetupPurchase) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: onReceived,
                                  child: const Text('Received'),
                                ),
                              ),
                            ],
                            if (isBuyer && isTrade) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: onProceed,
                                  child: const Text('Proceed'),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
            ),
          ),
        );
      },
    );
  }
}

class _TransactionRow {
  final Transaction tx;
  final ItemListing? item;
  final ItemListing? tradedItem;
  final Payment? payment;
  final AppUser? seller;

  const _TransactionRow({
    required this.tx,
    required this.item,
    required this.tradedItem,
    required this.payment,
    required this.seller,
  });
}

class _TxnThumb extends StatelessWidget {
  const _TxnThumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    if (url == null || url!.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Colors.grey),
      );
    }
    if (url!.startsWith('http')) {
      return Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey[200],
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }
    return Image.network(
      url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}


class FavouriteTab extends StatefulWidget {
  final AppUser user;
  const FavouriteTab({super.key, required this.user});

  @override
  State<FavouriteTab> createState() => _FavouriteTabState();
}

class  _FavouriteTabState extends State<FavouriteTab>{
  static const _cacheKey = 'favourite';
  final LocalProfileItemsRepository _cacheRepo = LocalProfileItemsRepository();
  late Future<List<ItemListing>> _futureItems;
  StreamSubscription? _streamSub;

  void initState() {
    super.initState();
    _futureItems = _loadCachedItems();
    _refreshRemoteItems();

    _streamSub = FavouriteRepository()
        .watchFavouriteIds(widget.user.id)
        .listen(
          (_) {
        print('🔥 Favourite stream triggered!');
        _refreshRemoteItems();
      },
      onError: (e) => print('Favourite stream error: $e'),
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
  Future<List<ItemListing>> _loadCachedItems() async {
    return _cacheRepo.listItems(userId: widget.user.id, tabKey: _cacheKey);
  }

  Future<void> _refreshRemoteItems() async {
    try {
      final remoteItems = await ItemsRepository().getFavouriteItems(widget.user.id);
      await _cacheRepo.replaceItems(
        userId: widget.user.id,
        tabKey: _cacheKey,
        items: remoteItems,
      );
      if (!mounted) return;
      setState(() {
        _futureItems = Future.value(remoteItems);
      });
    } catch (_) {
      // Keep cached list when refresh fails.
    }
  }

  void _showNetworkError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Network error. Please check your connection.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ItemListing>>(
      future: _futureItems,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _buildEmptyState(Icons.favorite_border, "No favourites yet");
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.8,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return GestureDetector(
              onTap: () {
                final navigator = Navigator.maybeOf(context);
                if (navigator == null) {
                  return;
                }
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(loginUser: widget.user, item: item),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildImage(
                          item.imageUrls.isNotEmpty ? item.imageUrls[0] : null,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.black.withOpacity(0.4),
                              Colors.transparent,
                            ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _StatusBadge(status: item.status, mini: true),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ItemTab extends StatefulWidget {
  final AppUser loginUser;
  final AppUser profileUser;
  final bool isOwnProfile;

  const ItemTab({super.key, required this.loginUser, required this.profileUser, this.isOwnProfile = false,});

  @override
  State<ItemTab> createState() => _ItemTabState();
}

class _ItemTabState extends State<ItemTab> {
  static const _cacheKey = 'your_item';
  final LocalProfileItemsRepository _cacheRepo = LocalProfileItemsRepository();
  late Future<List<ItemListing>> _futureItems;

  @override
  void initState() {
    super.initState();
    _futureItems = _loadCachedItems();
    _refreshRemoteItems();
  }

  Future<List<ItemListing>> _loadCachedItems() async {
    return _cacheRepo.listItems(userId: widget.profileUser.id, tabKey: _cacheKey);
  }

  Future<void> _refreshRemoteItems() async {
    try {
      final remoteItems = await ItemsRepository().getUserItems(widget.profileUser.id);
      await _cacheRepo.replaceItems(
        userId: widget.profileUser.id,
        tabKey: _cacheKey,
        items: remoteItems,
      );
      if (!mounted) return;
      setState(() {
        _futureItems = Future.value(remoteItems);
      });
    } catch (_) {
      // Keep cached list when refresh fails.
    }
  }

  void _showNetworkError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Network error. Please check your connection.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ItemListing>>(
      future: _futureItems,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _buildEmptyState(
            Icons.inventory_2_outlined,
            "No items listed yet",
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return GestureDetector(
              onTap: () {
                final navigator = Navigator.maybeOf(context);
                if (navigator == null) {
                  return;
                }
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(
                      loginUser: widget.loginUser, //widget.user = profile user ！= login user
                      item: item,
                    ),
                  ),
                ).then((result) {
                  if (!mounted) return;
                  if (result == true) {
                    setState(() {
                      _futureItems = _loadCachedItems();
                    });
                  }
                  _refreshRemoteItems();
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 80,
                            height: 80,
                            child: _buildImage(
                              item.imageUrls.isNotEmpty
                                  ? item.imageUrls[0]
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 65),
                                child: Text(
                                  item.name.toUpperCase(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF5B21B6),
                                  ),
                                ),
                              ),
                              if (item.repliedTo != null)
                                FutureBuilder<ItemListing?>(
                                  future: ItemsRepository().getById(
                                    item.repliedTo!,
                                  ),
                                  builder: (context, snap) {
                                    if (snap.hasData && snap.data != null) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 2,
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          "OFFERING FOR: ${snap.data!.name.toUpperCase()}",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange[800],
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              const SizedBox(height: 2),
                              if (item.repliedTo == null)
                                Text(
                                  item.listingType == 'both'
                                      ? 'FOR SALE / TRADE'
                                      : 'FOR ${item.listingType.toUpperCase()}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.purple[300],
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    size: 12,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat(
                                      'MMM d, yyyy',
                                    ).format(item.createdAt),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _StatusBadge(status: item.status),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool mini;
  const _StatusBadge({required this.status, this.mini = false});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toLowerCase()) {
      case 'available':
      case 'accepted':
        color = Colors.green;
        break;
      case 'confirmed':
        color = Colors.green;
        break;
      case 'pending':
        color = Colors.grey[400]!;
        break;
      case 'cancelled':
        color = Colors.red;
        break;
      case 'dropped':
      case 'rejected':
        color = Colors.red;
        break;
      case 'reserved':
        color = Colors.orange;
        break;
      default:
        color = Colors.blue;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: mini ? color.withOpacity(0.3) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

Widget _buildImage(String? url) {
  if (url == null || url.isEmpty) {
    return Container(
      color: Colors.grey[200],
      child: const Icon(Icons.image_outlined, color: Colors.grey),
    );
  }
  if (url.startsWith('http')) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
    );
  }
  if (url.startsWith('assets/')) {
    return Image.asset(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
    );
  }
  return Image.file(
    File(url),
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
  );
}

Widget _buildEmptyState(IconData icon, String message) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: Colors.grey)),
      ],
    ),
  );
}
