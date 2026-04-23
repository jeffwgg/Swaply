import 'package:flutter/material.dart';
import '../../../core/utils/app_snack_bars.dart';
import '../../../models/app_user.dart';
import '../../../models/item_listing.dart';
import '../../../repositories/items_repository.dart';
import '../../../repositories/favourite_repository.dart';
import '../../../services/supabase_service.dart';
import '../auth/login_screen.dart';
import '../item/item_detail_screen.dart';
import 'swipe_card.dart';

class SwipeHomeScreen extends StatefulWidget {
  final AppUser? user;
  const SwipeHomeScreen({super.key, this.user});

  @override
  State<SwipeHomeScreen> createState() => _SwipeHomeScreenState();
}

class _SwipeHomeScreenState extends State<SwipeHomeScreen>
    with TickerProviderStateMixin {
  List<ItemListing> _items = [];
  bool _loading = true;
  int _currentIndex = 0;

  // Swipe animation
  late AnimationController _swipeController;
  late Animation<Offset> _swipeAnimation;
  late Animation<double> _rotationAnimation;

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  bool _isAnimating = false;

  // Like / Nope overlay opacity
  double _likeOpacity = 0;
  double _nopeOpacity = 0;

  static const _swipeThreshold = 100.0;

  @override
  void initState() {
    super.initState();
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadItems();
  }

  @override
  void dispose() {
    _swipeController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final items = await ItemsRepository().getSwipeList(userId: widget.user?.id);
      setState(() {
        _items = items;
        _loading = false;
        _currentIndex = 0;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  ItemListing? get _currentItem =>
      _currentIndex < _items.length ? _items[_currentIndex] : null;

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isAnimating) return;
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta;
      final progress = _dragOffset.dx / _swipeThreshold;
      _likeOpacity = progress.clamp(0.0, 1.0);
      _nopeOpacity = (-progress).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isAnimating) return;
    if (_dragOffset.dx > _swipeThreshold) {
      _swipeRight();
    } else if (_dragOffset.dx < -_swipeThreshold) {
      _swipeLeft();
    } else {
      _resetCard();
    }
  }

  void _resetCard() {
    setState(() {
      _isDragging = false;
      _dragOffset = Offset.zero;
      _likeOpacity = 0;
      _nopeOpacity = 0;
    });
  }

  void _swipeRight() async {
    _isAnimating = true;
    final endOffset = Offset(500, _dragOffset.dy);

    _swipeAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: endOffset,
    ).animate(CurvedAnimation(
      parent: _swipeController,
      curve: Curves.easeOut,
    ));

    _swipeController.forward(from: 0).then((_) {
      _handleLike();
      _swipeController.reset();
      setState(() {
        _dragOffset = Offset.zero;
        _likeOpacity = 0;
        _nopeOpacity = 0;
        _isDragging = false;
        _isAnimating = false;
        _currentIndex++;
      });
    });
  }

  void _swipeLeft() {
    _isAnimating = true;
    final endOffset = Offset(-500, _dragOffset.dy);

    _swipeAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: endOffset,
    ).animate(CurvedAnimation(
      parent: _swipeController,
      curve: Curves.easeOut,
    ));

    _swipeController.forward(from: 0).then((_) {
      _swipeController.reset();
      setState(() {
        _dragOffset = Offset.zero;
        _likeOpacity = 0;
        _nopeOpacity = 0;
        _isDragging = false;
        _isAnimating = false;
        _currentIndex++;
      });
    });
  }

  void _handleLike() async {
    final item = _currentItem;
    if (item == null) return;

    final currentUser = SupabaseService.client.auth.currentUser;

    // Not logged in → show login prompt
    if (currentUser == null) {
      _showLoginPrompt(item);
      return;
    }

    try {
      await FavouriteRepository().toggleFavourite(currentUser.id, item.id);
      if (mounted) {
        AppSnackBars.favourite(context, added: true);
      }
    } catch (e) {
      print('Error saving favourite: $e');
    }
  }

  void _showLoginPrompt(ItemListing item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.favorite, color: Color(0xFF5A2CA0), size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Save to Favourites',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Login to save "${item.name}" and keep track of items you love.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B61FF), Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Login to Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Text(
                'Continue Browsing',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (widget.user == null) _buildLoginBanner(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: const Text(
          'Swaply',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A2CA0),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD8B4FE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_border, color: Color(0xFF5A2CA0), size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Login to save your favourite items ✨',
                style: TextStyle(color: Color(0xFF5A2CA0), fontSize: 13),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF5A2CA0), size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF5A2CA0)),
      );
    }

    if (_items.isEmpty || _currentIndex >= _items.length) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        Expanded(child: _buildCardStack()),
        const SizedBox(height: 4),
        const Text(
          '← swipe to skip  ·  swipe to like →',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 6),
        _buildActionButtons(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCardStack() {
    final remaining = _items.length - _currentIndex;
    final cards = <Widget>[];

    // Background cards (max 2)
    for (int i = (remaining - 1).clamp(0, 2); i >= 1; i--) {
      final item = _items[_currentIndex + i];
      cards.add(_buildStaticCard(item, i));
    }

    // Top card (draggable)
    if (_currentItem != null) {
      cards.add(_buildDraggableCard(_currentItem!));
    }

    return Stack(
      alignment: Alignment.center,
      children: cards,
    );
  }

  Widget _buildStaticCard(ItemListing item, int stackIndex) {
    final rotation = stackIndex == 1 ? -0.03 : 0.02;
    final offsetY = stackIndex * 10.0;

    return Transform(
      transform: Matrix4.identity()
        ..translate(0.0, offsetY)
        ..rotateZ(rotation),
      alignment: Alignment.center,
      child: SwipeCard(item: item, user: widget.user),
    );
  }

  Widget _buildDraggableCard(ItemListing item) {
    Offset offset = _isDragging ? _dragOffset : Offset.zero;
    if (_isAnimating) offset = _swipeAnimation.value;

    final rotation = offset.dx / 800;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Transform(
        transform: Matrix4.identity()
          ..translate(offset.dx, offset.dy)
          ..rotateZ(rotation),
        alignment: Alignment.center,
        child: Stack(
          children: [
            SwipeCard(item: item, user: widget.user),
            // LIKE overlay
            if (_likeOpacity > 0)
              Positioned(
                top: 20,
                left: 16,
                child: Opacity(
                  opacity: _likeOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF16A34A), width: 2),
                    ),
                    child: const Text(
                      'LIKE ♥',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            // NOPE overlay
            if (_nopeOpacity > 0)
              Positioned(
                top: 20,
                right: 16,
                child: Opacity(
                  opacity: _nopeOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDC2626), width: 2),
                    ),
                    child: const Text(
                      'NOPE ✕',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Skip button
          _ActionButton(
            icon: Icons.close_rounded,
            color: const Color(0xFFEF4444),
            bgColor: const Color(0xFFFEF2F2),
            borderColor: const Color(0xFFFCA5A5),
            size: 56,
            onTap: () {
              setState(() => _dragOffset = const Offset(-50, 0));
              Future.delayed(const Duration(milliseconds: 50), _swipeLeft);
            },
          ),
          // Info button
          _ActionButton(
            icon: Icons.info_outline_rounded,
            color: const Color(0xFF3B82F6),
            bgColor: const Color(0xFFEFF6FF),
            borderColor: const Color(0xFFBAE6FD),
            size: 44,
            onTap: () {
              if (_currentItem != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(
                      user: widget.user,
                      item: _currentItem!,
                    ),
                  ),
                );
              }
            },
          ),
          // Like button
          _ActionButton(
            icon: Icons.favorite_rounded,
            color: const Color(0xFF22C55E),
            bgColor: const Color(0xFFF0FDF4),
            borderColor: const Color(0xFF86EFAC),
            size: 56,
            onTap: () {
              setState(() => _dragOffset = const Offset(50, 0));
              Future.delayed(const Duration(milliseconds: 50), _swipeRight);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(
              Icons.celebration_rounded,
              size: 50,
              color: Color(0xFF5A2CA0),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "You've seen everything!",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Check back later for new listings",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _loadItems,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7B61FF), Color(0xFF5A3FFF)],
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Refresh',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action Button Widget ─────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  final double size;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: size * 0.45),
      ),
    );
  }
}