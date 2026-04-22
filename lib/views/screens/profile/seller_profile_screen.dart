import 'package:flutter/material.dart';

import '../../../models/app_user.dart';
import '../../../models/item_listing.dart';
import '../../../repositories/items_repository.dart';
import '../../../repositories/users_repository.dart';
import '../item/item_detail_screen.dart';

class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({
    super.key,
    required this.viewer,
    required this.sellerId,
  });

  final AppUser viewer;
  final String sellerId;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  late final Future<AppUser?> _sellerFuture =
      UsersRepository().getById(widget.sellerId);
  late final Future<List<ItemListing>> _itemsFuture =
      ItemsRepository().getUserItems(widget.sellerId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text('Seller Profile'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B1340),
        surfaceTintColor: Colors.transparent,
      ),
      body: FutureBuilder<AppUser?>(
        future: _sellerFuture,
        builder: (context, snapshot) {
          final seller = snapshot.data;
          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundImage: (seller?.profileImage != null &&
                              seller!.profileImage!.isNotEmpty)
                          ? NetworkImage(seller.profileImage!)
                          : const AssetImage('assets/sample.jpeg')
                              as ImageProvider,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        seller?.username ?? 'Seller',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF5B21B6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<ItemListing>>(
                  future: _itemsFuture,
                  builder: (context, itemsSnapshot) {
                    if (itemsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF5B21B6),
                        ),
                      );
                    }
                    if (itemsSnapshot.hasError) {
                      return Center(
                        child: Text('Error: ${itemsSnapshot.error}'),
                      );
                    }
                    final items = itemsSnapshot.data ?? [];
                    if (items.isEmpty) {
                      return const Center(
                        child: Text('No listings yet.'),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: items.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.82,
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final image = item.imageUrls.isNotEmpty
                            ? item.imageUrls.first
                            : null;
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ItemDetailsScreen(
                                  user: widget.viewer,
                                  item: item,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFE9D5FF)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                  child: image == null
                                      ? Image.asset(
                                          'assets/sample.jpeg',
                                          height: 130,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        )
                                      : (image.startsWith('http')
                                          ? Image.network(
                                              image,
                                              height: 130,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Image.asset(
                                                'assets/sample.jpeg',
                                                height: 130,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : Image.asset(
                                              image,
                                              height: 130,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Image.asset(
                                                'assets/sample.jpeg',
                                                height: 130,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            )),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (item.price != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'RM ${item.price!.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: Color(0xFF5B21B6),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

