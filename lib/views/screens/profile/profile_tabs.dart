import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:swaply/models/app_user.dart';
import 'package:swaply/models/item_listing.dart';
import 'package:swaply/models/payment.dart';
import 'package:swaply/models/transaction.dart';
import 'package:swaply/repositories/items_repository.dart';
import 'package:swaply/repositories/payments_repository.dart';
import 'package:swaply/repositories/transactions_repository.dart';
import 'package:swaply/repositories/users_repository.dart';
import 'package:swaply/views/screens/item/item_detail_screen.dart';
import 'package:swaply/views/screens/profile/seller_profile_screen.dart';
import 'package:swaply/views/screens/profile/transaction_detail_screen.dart';
import 'package:swaply/services/supabase_service.dart';

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

  @override
  void initState() {
    super.initState();
    _future = _loadRows();
  }

  void _reload() {
    setState(() {
      _future = _loadRows();
    });
  }

  Future<List<_TransactionRow>> _loadRows() async {
    final repo = TransactionsRepository();
    final paymentsRepo = PaymentsRepository();
    final itemsRepo = ItemsRepository();
    final usersRepo = UsersRepository();

    final buyerTxs = await repo.listForBuyer(widget.user.id);
    final sellerTxs = await repo.listForSeller(widget.user.id);

    final all = <Transaction>[
      ...buyerTxs,
      ...sellerTxs,
    ];

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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marked as received.')),
                );
                _reload();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to mark received: $e')),
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
                await TransactionsRepository().updateStatus(
                  transactionId: tx.transactionId,
                  transactionStatus: 'cancelled',
                );
                await PaymentsRepository().updateStatusForTransaction(
                  transactionId: tx.transactionId,
                  paymentStatus: 'refunded',
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cancelled. Refund will be issued in 3 working days.'),
                  ),
                );
                _reload();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to cancel: $e')),
                );
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
                        onChanged: _reload,
                      ),
                    ),
                  );
                  _reload();
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
                                        builder: (_) => SellerProfileScreen(
                                          viewer: widget.user,
                                          sellerId: row.seller!.id,
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
                            if (isBuyer) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: onReceived,
                                  child: const Text('Received'),
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
      return Image.asset(
        'assets/sample.jpeg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (url!.startsWith('http')) {
      return Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/sample.jpeg',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Image.asset(
      url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/sample.jpeg',
        width: size,
        height: size,
        fit: BoxFit.cover,
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
  List<ItemListing> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(); // ← 这里调用
  }

  // ✅ 加在这里
  Future<void> _load() async {
    print("🔥 _load called");
    setState(() => _loading = true);
    final items = await ItemsRepository().getFavouriteItems(widget.user.id);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ItemListing>>(
      future: ItemsRepository().getFavouriteItems(widget.user.id),
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
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(user: widget.user, item: item),
                  ),
                );
                _load();
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
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ItemListing>>(
      future: ItemsRepository().getUserItems(widget.profileUser.id),
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
              onTap: () async {
                ItemListing? repliedItem;
                if (item.repliedTo != null) {
                  repliedItem = await ItemsRepository().getById(
                    item.repliedTo!,
                  );
                }
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(
                      user: widget.loginUser, //widget.user = profile user ！= login user
                      item: repliedItem ?? item,
                    ),
                  ),
                );
                if (result == true) {
                  setState(() {});
                }
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
      case 'pending':
        color = Colors.green;
        break;
      case 'cancelled':
        color = Colors.amber;
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
      child: const Icon(Icons.image, color: Colors.grey),
    );
  }
  if (url.startsWith('http')) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
    );
  }
  return Image.asset(
    url,
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
