import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:swaply/models/app_user.dart';
import 'package:swaply/models/item_listing.dart';
import 'package:swaply/repositories/items_repository.dart';
import 'package:swaply/repositories/users_repository.dart';
import 'package:swaply/views/screens/item/item_detail_screen.dart';

class ProfileTabs extends StatefulWidget {
  final String userId;
  const ProfileTabs({super.key, required this.userId});

  @override
  State<ProfileTabs> createState() => _ProfileTabsState();
}

class _ProfileTabsState extends State<ProfileTabs> {
  AppUser? user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await UsersRepository().getById(widget.userId);
    if (mounted) {
      setState(() {
        this.user = user;
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

    return DefaultTabController(
      length: 4,
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
              Tab(text: "Review"),
              Tab(text: "Favourite"),
              Tab(text: "Your Item"),
              Tab(text: "Transaction"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ReviewTab(user: user!),
                FavouriteTab(user: user!),
                ItemTab(user: user!),
                TransactionTab(user: user!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewTab extends StatelessWidget {
  final AppUser user;
  const ReviewTab({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return _buildEmptyState(Icons.rate_review_outlined, "No reviews yet");
  }
}

class TransactionTab extends StatelessWidget {
  final AppUser user;
  const TransactionTab({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return _buildEmptyState(Icons.receipt_long_outlined, "No transactions yet");
  }
}

class FavouriteTab extends StatelessWidget {
  final AppUser user;
  const FavouriteTab({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ItemListing>>(
      future: ItemsRepository().getFavouriteItems(user.id),
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
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(user: user, item: item),
                  ),
                );
                if (result == true) {
                  // Trigger a rebuild to refresh the list if needed
                  (context as Element).markNeedsBuild();
                }
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
  final AppUser user;
  const ItemTab({super.key, required this.user});

  @override
  State<ItemTab> createState() => _ItemTabState();
}

class _ItemTabState extends State<ItemTab> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ItemListing>>(
      future: ItemsRepository().getUserItems(widget.user.id),
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
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(
                      user: widget.user,
                      item: item,
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
      case 'dropped':
      case 'rejected':
        color = Colors.red;
        break;
      case 'reserved':
      case 'pending':
        color = Colors.orange;
        break;
      default:
        color = Colors.blue;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
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
