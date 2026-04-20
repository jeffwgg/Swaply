import 'dart:developer';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:swaply/repositories/users_repository.dart';
import '../../../models/app_user.dart';
import '../../../models/item_listing.dart';
import '../../../repositories/favourite_repository.dart';
import '../../../repositories/items_repository.dart';
import '../../../services/follow_service.dart';
import '../auth/login_screen.dart';
import 'create_item_screen.dart';
import '../profile/profile_screen.dart';
import '../../../services/supabase_service.dart';
import  'package:supabase_flutter/supabase_flutter.dart';
class ItemDetailsScreen extends StatefulWidget {
  final AppUser? user;
  final ItemListing item;
  const ItemDetailsScreen({this.user, required this.item, super.key});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  late final AppUser? user;
  String _ownerName = '';
  List<ItemListing> _replies = [];
  final Map<int, String> _replyOwnerNames = {};
  int _currentImageIndex = 0;
  bool _isFollowing = false;
  bool _isLoadingFollow = false;
  bool _isFavourite = false;
  int _favCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      user = widget.user;
      _isFavourite = widget.item.isFavorite;
    }
    _fetchOwner();
    _fetchReplies();
    _fetchFavouriteCount();
    _loadFollowState();
  }

  Future<void> _loadFollowState() async {
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser == null || currentUser.id == widget.item.ownerId) return;

    final following = await FollowService.isFollowing(
      currentUser.id,
      widget.item.ownerId,
    );

    if (!mounted) return;
    setState(() => _isFollowing = following);
  }

  void _showFollowError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _fetchOwner() async {
    final user = await UsersRepository().getById(widget.item.ownerId);
    if (mounted) {
      setState(() {
        _ownerName = user?.username ?? 'Unknown';
      });
    }
  }

  Future<void> _fetchReplies() async {
    try {
      final replies = await ItemsRepository().getReplyList(widget.item.id);
      for (var r in replies) {
        final user = await UsersRepository().getById(r.ownerId);
        _replyOwnerNames[r.id] = user?.username ?? 'Unknown';
      }
      if (mounted) {
        setState(() {
          _replies = replies;
        });
      }
    } catch (e) {
      log('Error fetching replies: $e');
    }
  }

  Future<void> _fetchFavouriteCount() async {
    final count = await FavouriteRepository().getFavouriteCount(widget.item.id);
    if (mounted) {
      setState(() {
        _favCount = count;
      });
    }
  }

  Widget _buildImage(
    String url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 50),
      );
    }
    return Image.asset(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image, size: 50),
    );
  }

  Future<void> _toggleFavourite() async {
    if (widget.user == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    try {
      final newState = await FavouriteRepository().toggleFavourite(
        widget.user!.id,
        widget.item.id,
      );
      setState(() {
        widget.item.isFavorite = newState;
        _isFavourite = newState;
        _isFavourite ? _favCount++ : _favCount--;
      });
    } catch (e) {
      log("Favourite error: $e");
    }
  }

  Future<void> _dropListing() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Drop Listing'),
        content: const Text('Are you sure you want to drop this listing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Drop'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ItemsRepository().dropListing(widget.item.id);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _dropReply(int id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Drop Trade Offer'),
        content: const Text('Are you sure you want to drop this trade offer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Drop'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ItemsRepository().dropListing(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offer dropped successfully')),
          );
          _fetchReplies();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error dropping offer: $e')));
        }
        log("Error dropping offer: $e");
      }
    }
  }

  Future<void> _acceptReply(int replyId) async {
    for (var r in _replies) {
      if (r.id == replyId) {
        await ItemsRepository().updateStatus('accepted', r.id);
      } else if (r.status != 'dropped') {
        await ItemsRepository().updateStatus('rejected', r.id);
      }
    }
    await ItemsRepository().updateStatus('reserved', widget.item.id);
  }

  Future<void> _rejectReply(int replyId) async {
    await ItemsRepository().updateStatus('rejected', replyId);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final user = widget.user;
    const accent = Color(0xFF5B21B6);
    const accentSoft = Color(0xFFF3E8FF);

    print("CURRENT USER: ${user?.id}");
  print("ITEM OWNER: ${item.ownerId}");
  print(SupabaseService.client.rest.url);
  

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(
                    ),
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundImage: AssetImage('assets/sample.jpeg'),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                    child: Text(_ownerName, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            if (user == null || user.id != item.ownerId)
              TextButton(
                onPressed: _isLoadingFollow
                    ? null
                    : () async {
                        final currentUser = SupabaseService.client.auth.currentUser;
                        final targetUserId = item.ownerId;

                        print("USER ID: ${currentUser?.id}");
                        print("SESSION: ${SupabaseService.client.auth.currentSession}");
                         print("USER ID: $targetUserId");
                         print("JWT: ${SupabaseService.client.auth.currentSession?.accessToken}");
                         print("TOKEN: ${Supabase.instance.client.auth.currentSession?.accessToken}");
                        if (currentUser == null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                          return;
                        }

                        if (currentUser.id == targetUserId) {
                          _showFollowError('You cannot follow yourself.');
                          return;
                        }

                        setState(() => _isLoadingFollow = true);

                        try {
                          final bool wasFollowing = _isFollowing;
                          final success = wasFollowing
                              ? await FollowService.unfollowUser(currentUser.id, targetUserId)
                              : await FollowService.followUser(currentUser.id, targetUserId);

                          if (!mounted) return;

                          if (!success) {
                            setState(() => _isLoadingFollow = false);
                            _showFollowError(
                              _isFollowing
                                  ? 'Unable to unfollow right now.'
                                  : 'Unable to follow right now.',
                            );
                            return;
                          }

                          setState(() {
                            _isFollowing = !wasFollowing;
                            _isLoadingFollow = false;
                          });

                          if (mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_isFollowing
                                    ? 'Following now!'
                                    : 'Unfollowed successfully.'),
                                backgroundColor: _isFollowing
                                    ? Colors.green
                                    : Colors.grey[700],
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        } catch (e) {
                          print('Follow error: $e');
                          if (mounted) {
                            setState(() => _isLoadingFollow = false);
                            _showFollowError(
                                'Error updating follow state. Please try again.');
                          }
                        }
                      },
                style: TextButton.styleFrom(
                  backgroundColor: _isFollowing
                      ? const Color(0xFF5B21B6)
                      : Colors.transparent,
                  side: BorderSide(
                    color: const Color(0xFF5B21B6),
                    width: _isFollowing ? 0 : 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _isFollowing ? 'Following' : 'Follow',
                  style: TextStyle(
                    color: _isFollowing
                        ? Colors.white
                        : const Color(0xFF5B21B6),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Color(0xFF5B21B6)),
            onPressed: () {
              // todo: share functionality
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrls.isNotEmpty)
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE9D5FF)),
                      ),
                      child: CarouselSlider(
                        options: CarouselOptions(
                          height: 250,
                          viewportFraction: 1.0,
                          enlargeCenterPage: false,
                          enableInfiniteScroll: item.imageUrls.length > 1,
                          onPageChanged: (index, reason) {
                            setState(() {
                              _currentImageIndex = index;
                            });
                          },
                        ),
                        items: item.imageUrls.map((url) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _buildImage(
                              url,
                              width: double.infinity,
                              height: 250,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (item.imageUrls.length > 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: item.imageUrls.asMap().entries.map((entry) {
                          return Container(
                            width: 8.0,
                            height: 8.0,
                            margin: const EdgeInsets.symmetric(
                              vertical: 10.0,
                              horizontal: 4.0,
                            ),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.deepPurple)
                                      .withOpacity(
                                        _currentImageIndex == entry.key
                                            ? 0.9
                                            : 0.4,
                                      ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                )
              else
                Container(
                  height: 250,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.image, size: 100, color: Colors.grey),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            color: Color(0xFF5B21B6),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Posted on ${DateFormat('MMM d, yyyy').format(item.createdAt)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _toggleFavourite,
                        icon: Icon(
                          _isFavourite ? Icons.favorite : Icons.favorite_border,
                          color: _isFavourite ? Colors.red : Color(0xFF5B21B6),
                          size: 28,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_favCount',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5B21B6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                item.description,
                style: const TextStyle(fontSize: 16, color: Color(0xFF7C3AED)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: accentSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD5BFFD)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CATEGORY',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFFA78BFA),
                              ),
                            ),
                            Text(
                              item.category,
                              style: const TextStyle(
                                fontSize: 22,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: item.status == 'available'
                            ? Color(0xFFE6FEE1)
                            : item.status == 'dropped'
                            ? Color(0xFFFFC0C4)
                            : Color(0xFFF2ECFF),
                        borderRadius: BorderRadius.circular(10),
                        border: item.status == 'available'
                            ? Border.all(color: const Color(0xFFAFF9B6))
                            : item.status == 'dropped'
                            ? Border.all(color: const Color(0xFFFFA0A2))
                            : Border.all(color: const Color(0xFFD5BFFD)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'STATUS',
                              style: TextStyle(
                                fontSize: 16,
                                color: item.status == 'available'
                                    ? Color(0xFF65BE4A)
                                    : item.status == 'dropped'
                                    ? Color(0xFFFF3E41)
                                    : Color(0xFF7C3AED),
                              ),
                            ),
                            Text(
                              item.status[0].toUpperCase() +
                                  item.status.substring(1).toLowerCase(),
                              style: TextStyle(
                                fontSize: 22,
                                color: item.status == 'available'
                                    ? const Color(0xFF2D7D26)
                                    : item.status == 'dropped'
                                    ? const Color(0xFFDE1518)
                                    : const Color(0xFF5B21B6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (item.listingType != 'trade')
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: const Border(
                      left: BorderSide(color: Color(0xFF5B21B6), width: 5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.sell_outlined,
                              color: Color(0xFF5B21B6),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Price',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                            Expanded(child: SizedBox()),
                            Text(
                              'RM ${item.price!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (item.listingType != 'sell')
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: const Border(
                      left: BorderSide(color: Color(0xFF5B21B6), width: 5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.transfer_within_a_station,
                              color: Color(0xFF5B21B6),
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Trade Preferences',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          item.preference ?? 'None',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (item.latitude != null && item.longitude != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),

                    const Text(
                      "Location",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5B21B6),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE9D5FF)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(item.latitude!, item.longitude!),
                            zoom: 15,
                          ),
                          markers: {
                            Marker(
                              markerId: const MarkerId("item_location"),
                              position: LatLng(item.latitude!, item.longitude!),
                            ),
                          },
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                          liteModeEnabled: true, // ✅ smoother in scroll view
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    if (item.address != null)
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.address!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              if (item.listingType != 'sell')
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Public Trade Offers',
                        style: TextStyle(
                          fontSize: 20,
                          color: Color(0xFF5B21B6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: accentSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC9AFF9)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          '${_replies.length} ACTIVE',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              ..._replies.map((reply) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: reply.imageUrls.isNotEmpty
                                  ? _buildImage(
                                      reply.imageUrls[0],
                                      height: 100,
                                      width: 100,
                                    )
                                  : const Icon(Icons.image, size: 100),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 60,
                                            ),
                                            child: Text(
                                              reply.name.toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 20,
                                                color: Color(0xFF5B21B6),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (user != null &&
                                            user.id == reply.ownerId)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () =>
                                                _dropReply(reply.id),
                                          ),
                                      ],
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ProfileScreen(
                                            
                                            ),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircleAvatar(
                                            radius: 12,
                                            backgroundImage: AssetImage(
                                              'assets/sample.jpeg',
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              0,
                                              0,
                                              16,
                                              0,
                                            ),
                                            child: Text(
                                              _replyOwnerNames[reply.id]!,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                color: Color(0xFF7C3AED),
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
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
                                          ).format(reply.createdAt),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (item.status != 'dropped')
                                      if (user != null &&
                                          user.id == item.ownerId &&
                                          reply.status == 'pending')
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextButton(
                                                onPressed: () {
                                                  _acceptReply(reply.id);
                                                },
                                                style: TextButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFF5B21B6,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                      ),
                                                ),
                                                child: const Text(
                                                  'Accept',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextButton(
                                                onPressed: () {
                                                  _rejectReply(reply.id);
                                                },
                                                style: TextButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFE9E1FE,
                                                  ),
                                                  foregroundColor: accent,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                      ),
                                                ),
                                                child: const Text(
                                                  'Reject',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Color(0xFF5B21B6),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _StatusBadge(status: reply.status),
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 14),
              if (user != null && user.id == item.ownerId)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  CreateItemScreen(user: user, item: item),
                            ),
                          );
                          if (result == true && mounted) {
                            Navigator.pop(context, true);
                          }
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Edit Listing',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: _dropListing,
                        style: TextButton.styleFrom(
                          backgroundColor: accentSoft,
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(
                              color: Color(0xFF7C3AED),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Drop Listing',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                if (item.listingType == 'both')
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            if (user == null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                              return;
                            }
                            //todo: link to transaction page
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Buy Now',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            if (user == null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                              return;
                            }
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreateItemScreen(
                                  user: user,
                                  repliedTo: item.id,
                                ),
                              ),
                            );
                            if (result == true) _fetchReplies();
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: accentSoft,
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(
                                color: Color(0xFF7C3AED),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Offer Trade',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (item.listingType == 'sell')
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        if (user == null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                          return;
                        }
                        //todo: link to transaction page
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Buy Now',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  )
                else if (item.listingType == 'trade')
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () async {
                        if (user == null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                          return;
                        }
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateItemScreen(
                              user: user,
                              repliedTo: item.id,
                            ),
                          ),
                        );
                        if (result == true) _fetchReplies();
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: accentSoft,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(
                            color: Color(0xFF7C3AED),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Offer Trade',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toLowerCase()) {
      case 'available': color = Colors.green; break;
      case 'dropped': color = Colors.red; break;
      case 'reserved': color = Colors.orange; break;
      case 'accepted':
      case 'pending':
      default: color = Colors.blue;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
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
