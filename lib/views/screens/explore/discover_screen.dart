import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:bubble_tab_indicator/bubble_tab_indicator.dart';
import 'package:swaply/models/item_listing.dart';
import 'package:swaply/repositories/items_repository.dart';
import 'package:swaply/views/screens/auth/login_screen.dart';
import '../../../models/app_user.dart';
import '../../../repositories/favourite_repository.dart';
import '../item/item_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  final AppUser? user;

  const DiscoverScreen({super.key, this.user});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  final List<String> _categories = const [
    'All',
    'Electronics',
    'Fashion',
    'Home',
    'Books',
    'Toys',
    'Others',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20.0, 50.0, 20.0, 8.0),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : const Icon(Icons.tune),
                  labelText: 'Search',
                  hintText: 'Search items, trades or sellers',
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(10.0)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TabBar(
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: const BubbleTabIndicator(
                  indicatorHeight: 30.0,
                  indicatorColor: Colors.deepPurple,
                  indicatorRadius: 10.0,
                  tabBarIndicatorSize: TabBarIndicatorSize.tab,
                ),
                tabs: _categories.map((cat) {
                  if (cat == 'All') {
                    return const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.format_list_bulleted, size: 18),
                          SizedBox(width: 6),
                          Text("All"),
                        ],
                      ),
                    );
                  }
                  return Tab(text: cat);
                }).toList(),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: TabBarView(
                  children: _categories
                      .map(
                        (cat) => NestedTabBar(
                          outerTab: cat,
                          user: widget.user,
                          searchQuery: _searchQuery,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NestedTabBar extends StatefulWidget {
  final String outerTab;
  final AppUser? user;
  final String searchQuery;
  const NestedTabBar({
    required this.outerTab,
    required this.searchQuery,
    this.user,
    super.key,
  });

  @override
  State<NestedTabBar> createState() => _NestedTabBarState();
}

class _NestedTabBarState extends State<NestedTabBar>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  final List<String> _types = const ['All Items', 'For Sale', 'For Trade'];

  late Future<List<ItemListing>> _futureItems;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _types.length, vsync: this);

    _loadItems();

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _loadItems();
      });
    });
  }

  void _loadItems() {
    _futureItems = ItemsRepository().getDiscoverList(
      userId: widget.user?.id,
      category: widget.outerTab,
      listingType: _types[_tabController.index] == 'For Sale'
          ? 'sell'
          : _types[_tabController.index] == 'For Trade'
          ? 'trade'
          : 'both',
      searchQuery: widget.searchQuery,
    );
  }

  @override
  void didUpdateWidget(covariant NestedTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.user != widget.user ||
        oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.outerTab != widget.outerTab) {
      _loadItems();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: TabBar.secondary(
              controller: _tabController,
              dividerColor: Colors.transparent,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              isScrollable: true,
              labelColor: Colors.deepPurple,
              unselectedLabelColor: Colors.purple,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: const BubbleTabIndicator(
                indicatorHeight: 40.0,
                indicatorColor: Colors.white,
                indicatorRadius: 10.0,
                tabBarIndicatorSize: TabBarIndicatorSize.tab,
              ),
              tabs: _types.map((type) => Tab(text: type)).toList(),
            ),
          ),
        ),

        const SizedBox(height: 10),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _types.map((type) {
              return FutureBuilder<List<ItemListing>>(
                future: _futureItems,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final items = snapshot.data ?? [];

                  if (items.isEmpty) {
                    return const Center(child: Text('No items found.'));
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    itemCount: items.length,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    itemBuilder: (context, index) =>
                        ItemCard(
                          user: widget.user, 
                          item: items[index],
                          onRefresh: () {
                            setState(() {
                              _loadItems();
                            });
                          },
                        ),
                  );
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class ItemCard extends StatefulWidget {
  final AppUser? user;
  final ItemListing item;
  final VoidCallback? onRefresh;

  const ItemCard({super.key, this.user, required this.item, this.onRefresh});

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  late bool isFav;

  @override
  void initState() {
    super.initState();
    isFav = widget.item.isFavorite ?? false;
  }

  Widget _buildImage(String url) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        height: 150,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
      );
    }
    return Image.asset(
      url,
      height: 120,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
    );
  }

  Future<void> _toggleFavourite() async {
    if (widget.user == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    try {
      final repo = FavouriteRepository();

      final newState = await repo.toggleFavourite(
        widget.user!.id,
        widget.item.id,
      );

      setState(() {
        isFav = newState;
      });
    } catch (e) {
      log("Favourite error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ItemDetailsScreen(user: widget.user, item: widget.item),
          ),
        );
        if (result == true) {
          if (widget.onRefresh != null) {
            widget.onRefresh!();
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: widget.item.imageUrls.isNotEmpty
                      ? _buildImage(widget.item.imageUrls[0])
                      : const SizedBox(
                          height: 120,
                          width: double.infinity,
                          child: Icon(Icons.image, size: 50),
                        ),
                ),

                /// PRICE & TRADE TAGS
                Positioned(
                  top: 10,
                  left: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.item.price != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'RM ${widget.item.price!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (widget.item.listingType == 'trade' ||
                          widget.item.listingType == 'both')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'TRADE',
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),

                Positioned(
                  top: 10,
                  right: 10,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      onPressed: _toggleFavourite,
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.location_on, size: 14),
                      SizedBox(width: 4),
                      Text('0.8 miles away'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
