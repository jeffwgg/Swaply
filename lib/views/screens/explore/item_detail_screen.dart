import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:swaply/repositories/users_repository.dart';
import '../../../models/item_listing.dart';
import '../../../repositories/items_repository.dart';
import '../item/create_item_screen.dart';

class ItemDetailsScreen extends StatefulWidget {
  final ItemListing item;
  const ItemDetailsScreen(this.item, {super.key});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  String _ownerName = '';
  List<ItemListing> _replies = [];
  final Map<int, String> _replyOwnerNames = {};
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchOwner();
    _fetchReplies();
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
      debugPrint('Error fetching replies: $e');
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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final int loginId = 3; //todo: get real logged-in user ID

    return Scaffold(
      appBar: AppBar(title: const Text('Item Details')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrls.isNotEmpty)
                Column(
                  children: [
                    CarouselSlider(
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
                              color: (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.deepPurple)
                                  .withOpacity(
                                      _currentImageIndex == entry.key
                                          ? 0.9
                                          : 0.4),
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
              const SizedBox(height: 24),
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 24,
                  color: Color(0xFF5B21B6),
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person,
                    color: Color(0xFF7C3AED),
                    size: 18.0,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _ownerName.isEmpty ? 'Unknown' : '@$_ownerName',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEDE9FE)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.listingType != 'trade') ...[
                              const Text(
                                'Asking Price',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFA78BFA),
                                ),
                              ),
                              Text(
                                'RM ${item.price!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Color(0xFF5B21B6),
                                ),
                              ),
                            ] else ...[
                              const Text(
                                'Only For Trade',
                                style: TextStyle(
                                  fontSize: 24,
                                  color: Color(0xFF5B21B6),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9E1FE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC9AFF9)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Status',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                            Text(
                              item.status[0].toUpperCase() +
                                  item.status.substring(1).toLowerCase(),
                              style: const TextStyle(
                                fontSize: 24,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF5B21B6), width: 5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            color: Color(0xFF5B21B6),
                            size: 20,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Item Description',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5B21B6),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        item.description,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (item.listingType != 'sell')
                Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF5B21B6), width: 5),
                  ),
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
                          SizedBox(width: 5),
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
                        item.preference!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
                      color: const Color(0xFFE9E1FE),
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
                  ),
                  child: Padding(
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
                                Text(
                                  reply.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    color: Color(0xFF5B21B6),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      color: Color(0xFF7C3AED),
                                      size: 18.0,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '@${_replyOwnerNames[reply.id] ?? '...'}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Color(0xFF7C3AED),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (item.status != 'dropped')
                                  if (loginId == item.ownerId &&
                                      reply.status == 'pending')
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () {},
                                            style: TextButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF5B21B6,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
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
                                            onPressed: () {},
                                            style: TextButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFFE9E1FE,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
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
                                    )
                                  else ...[
                                    Text(
                                      reply.status[0].toUpperCase() +
                                          reply.status.substring(1),
                                    ),
                                  ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 10),
              if (loginId == item.ownerId)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFE9E1FE),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                          color: Color(0xFF7C3AED),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Drop Listing',
                      style: TextStyle(fontSize: 16, color: Color(0xFF7C3AED)),
                    ),
                  ),
                )
              else ...[
                if (item.listingType == 'both')
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            //todo: link to transaction page
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFF5B21B6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    CreateItemScreen(repliedTo: item.id),
                              ),
                            );
                            if (result == true) {
                              _fetchReplies();
                            }
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFE9E1FE),
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(
                                color: Color(0xFF7C3AED),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                        //todo: link to transaction page
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF5B21B6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CreateItemScreen(repliedTo: item.id),
                          ),
                        );
                        if (result == true) {
                          _fetchReplies();
                        }
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE9E1FE),
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(
                            color: Color(0xFF7C3AED),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
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
