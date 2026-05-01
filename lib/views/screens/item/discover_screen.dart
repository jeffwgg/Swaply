import 'dart:developer';
import 'dart:async';
import 'dart:io';
import '../../../services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:bubble_tab_indicator/bubble_tab_indicator.dart';
import 'package:swaply/models/item_listing.dart';
import 'package:swaply/repositories/users_repository.dart';
import 'package:swaply/views/screens/auth/login_screen.dart';
import '../../../models/app_user.dart';
import '../../../services/item_service.dart';
import 'item_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  final AppUser? user;

  const DiscoverScreen({super.key, this.user});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _searchHistoryDebounce;
  List<String> _recentSearches = [];
  bool _showSearchHistory = false;
  int _reloadToken = 0;
  StreamSubscription? _favStream;

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
  void initState() {
    super.initState();
    _loadRecentSearches();
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _showSearchHistory =
            _searchFocusNode.hasFocus &&
            _recentSearches.isNotEmpty &&
            _searchController.text.trim().isEmpty;
      });
    });
    if (widget.user != null) {
      _favStream = SupabaseService.client
          .from('favourites')
          .stream(primaryKey: ['id'])
          .eq('user_id', widget.user!.id)
          .listen((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _reloadDiscover();
        });
      });
    }
  }

  @override
  void dispose() {
    _favStream?.cancel();
    _searchHistoryDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final recents = await ItemService().loadRecentSearchQueries();
    if (!mounted) return;
    setState(() {
      _recentSearches = recents;
      _showSearchHistory =
          _searchFocusNode.hasFocus &&
          _recentSearches.isNotEmpty &&
          _searchController.text.trim().isEmpty;
    });
  }

  void _reloadDiscover() {
    setState(() {
      _reloadToken++;
    });
  }

  Future<void> _reloadDiscoverAsync() async {
    _reloadDiscover();
  }

  void _saveSearchHistory(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }
    _searchHistoryDebounce?.cancel();
    _searchHistoryDebounce = Timer(const Duration(milliseconds: 600), () async {
      await ItemService().saveSearchQuery(normalized);
      await _loadRecentSearches();
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5B21B6);
    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE9D5FF)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepPurple.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onTap: () {
                          setState(() {
                            _showSearchHistory =
                                _recentSearches.isNotEmpty &&
                                _searchController.text.trim().isEmpty;
                          });
                        },
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                            _showSearchHistory =
                                _searchFocusNode.hasFocus &&
                                _recentSearches.isNotEmpty &&
                                value.trim().isEmpty;
                          });
                          _saveSearchHistory(value);
                        },
                        onSubmitted: _saveSearchHistory,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, color: accent),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, color: accent),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _showSearchHistory =
                                    _searchFocusNode.hasFocus &&
                                    _recentSearches.isNotEmpty;
                              });
                            },
                          ),
                          labelText: 'Search listings',
                          labelStyle: const TextStyle(color: accent),
                          hintText: 'Search items or sellers',
                          filled: true,
                          fillColor: Colors.transparent,
                          border: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(14.0)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TabBar(
                      dividerColor: Colors.transparent,
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: Colors.white,
                      unselectedLabelColor: accent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: const BubbleTabIndicator(
                        indicatorHeight: 30.0,
                        indicatorColor: accent,
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
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: _categories
                            .map(
                              (cat) => NestedTabBar(
                                outerTab: cat,
                                user: widget.user,
                                searchQuery: _searchQuery,
                                reloadToken: _reloadToken,
                                onRefreshParent: _reloadDiscover,
                                onPullToRefresh: _reloadDiscoverAsync,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
                if (_showSearchHistory)
                  Positioned(
                    top: 58,
                    left: 0,
                    right: 0,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Recent searches',
                                      style: TextStyle(
                                        color: Color(0xFF5B21B6),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await ItemService().clearSearchHistory();
                                      if (!mounted) return;
                                      setState(() {
                                        _recentSearches = [];
                                        _showSearchHistory = false;
                                      });
                                    },
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFF3E8FF)),
                            ..._recentSearches.take(5).map((history) {
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.history_rounded,
                                  size: 18,
                                  color: Color(0xFF7C3AED),
                                ),
                                title: Text(
                                  history,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF5B21B6)),
                                ),
                                onTap: () {
                                  _searchController.text = history;
                                  setState(() {
                                    _searchQuery = history;
                                    _showSearchHistory = false;
                                  });
                                  _saveSearchHistory(history);
                                  FocusScope.of(context).unfocus();
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
  final int reloadToken;
  final VoidCallback? onRefreshParent;
  final Future<void> Function()? onPullToRefresh;
  const NestedTabBar({
    required this.outerTab,
    required this.searchQuery,
    required this.reloadToken,
    this.onRefreshParent,
    this.onPullToRefresh,
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
    _futureItems = ItemService().loadItems(
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
        oldWidget.outerTab != widget.outerTab ||
        oldWidget.reloadToken != widget.reloadToken) {
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
    const accent = Color(0xFF5B21B6);
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF3E8FF),
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: const Color(0xFFE9D5FF)),
          ),
          child: TabBar.secondary(
            controller: _tabController,
            dividerColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            isScrollable: false,
            labelColor: accent,
            unselectedLabelColor: const Color(0xFF7C3AED),
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

        const SizedBox(height: 10),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _types.map((type) {
              return FutureBuilder<List<ItemListing>>(
                future: _futureItems,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: accent),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Could not load items right now. Please try again.'),
                    );
                  }

                  final items = snapshot.data ?? [];

                  if (items.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: widget.onPullToRefresh ?? () async {},
                      color: accent,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 18),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE9D5FF)),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 38, color: accent),
                                SizedBox(height: 10),
                                Text(
                                  'No items found',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Try changing category or search words.',
                                  style: TextStyle(color: Color(0xFF7C3AED)),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: widget.onPullToRefresh ?? () async {},
                    color: accent,
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: ScrollController()
                        ..addListener(() {
                          FocusScope.of(context).unfocus();
                        }),
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
                              widget.onRefreshParent?.call();
                              setState(() {
                                _loadItems();
                              });
                            },
                          ),
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
  Future<AppUser?>? _ownerFuture;

  @override
  void initState() {
    super.initState();
    _ownerFuture = UsersRepository().getById(widget.item.ownerId);
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
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
      );
    }
    return Image.file(
      File(url),
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

    final previousState = widget.item.isFavorite;
    setState(() {
      widget.item.isFavorite = !previousState;
    });

    try {
      final newState = await ItemService().toggleFavourite(
        widget.item.id,
        widget.user!.id,
      );
      if (!mounted) return;
      setState(() {
        widget.item.isFavorite = newState;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        widget.item.isFavorite = previousState;
      });
      log("Favourite error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (!mounted) return;
        final navigator = Navigator.maybeOf(context);
        if (navigator == null) {
          return;
        }
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ItemDetailsScreen(loginUser: widget.user, item: widget.item),
          ),
        );
        if (!mounted) return;

        setState(() {});

        if (widget.onRefresh != null) {
          widget.onRefresh!();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9D5FF)),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
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
                    radius: 16,
                    child: IconButton(
                      onPressed: _toggleFavourite,
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        widget.item.isFavorite ? Icons.favorite : Icons.favorite_border,
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
                  Row(
                    children: [
                      FutureBuilder<AppUser?>(
                        future: _ownerFuture,
                        builder: (context, snapshot) {
                          final owner = snapshot.data;
                          final image = owner?.profileImage;
                          final avatar = image != null && image.isNotEmpty
                              ? (image.startsWith('http')
                                    ? NetworkImage(image)
                                    : AssetImage(image) as ImageProvider)
                              : null;
                          return CircleAvatar(
                            radius: 9,
                            backgroundImage: avatar,
                            child: avatar == null
                                ? const Icon(Icons.person, size: 10)
                                : null,
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FutureBuilder<AppUser?>(
                          future: _ownerFuture,
                          builder: (context, snapshot) {
                            final ownerName =
                                (snapshot.data?.username  ?? 'Unknown')
                                    .trim();
                            return Text(
                              ownerName.isEmpty ? 'Unknown' : ownerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF7C3AED)),
                            );
                          },
                        ),
                      ),
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
