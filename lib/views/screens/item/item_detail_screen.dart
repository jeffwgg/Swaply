import 'dart:developer';
import 'dart:io';
import 'dart:convert';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:swaply/repositories/users_repository.dart';
import '../../../core/utils/app_snack_bars.dart';
import '../../../models/app_user.dart';
import '../../../models/checkout_flow_kind.dart';
import '../../../models/item_listing.dart';
import '../../../models/meetup_address_option.dart';
import '../../../models/transaction.dart';
import '../../../repositories/favourite_repository.dart';
import '../../../repositories/items_repository.dart';
import '../../../repositories/transactions_repository.dart';
import '../../../services/chat_service.dart';
import '../../../services/item_service.dart';
import '../../../services/notification_service.dart';
import '../auth/login_screen.dart';
import '../transaction/checkout_screen.dart';
import 'create_item_screen.dart';
import '../profile/profile_screen.dart';
import '../../../services/follow_service.dart';

class ItemDetailsScreen extends StatefulWidget {
  final AppUser? loginUser;
  final ItemListing item;
  const ItemDetailsScreen({this.loginUser, required this.item, super.key});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  late final AppUser? loginUser;
  late ItemListing _item;
  AppUser? _owner;
  List<ItemListing> _replies = [];
  final Map<int, String> _replyOwnerNames = {};
  final Map<int, AppUser?> _replyOwners = {};
  int _currentImageIndex = 0;
  bool _isFollowing = false;
  bool _isFavourite = false;
  int? _favCount;
  bool _isLoadingFollow = false;
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    _item = widget.item;

    // logged in
    if (widget.loginUser != null) {
      loginUser = widget.loginUser;
      _isFavourite = _item.isFavorite;
      _loadFollowState();
    }
    _fetchOwner();
    _fetchReplies();
    _fetchFavouriteCount();
  }

  Future<void> _loadFollowState() async {
    if (loginUser!.id == _item.ownerId) {
      return;
    }
    final following = await FollowService.isFollowing(
      loginUser!.id,
      _item.ownerId,
    );

    if (!mounted) return;
    setState(() => _isFollowing = following);
  }

  Future<void> _fetchOwner() async {
    AppUser? owner;
    try {
      owner = await UsersRepository().getById(_item.ownerId);
    } catch (e) {
      log('Owner lookup fallback used: $e');
    }
    if (mounted) {
      setState(() {
        _owner = owner;
      });
    }
  }

  Future<void> _fetchReplies() async {
    try {
      final replies = await ItemsRepository().getReplyList(_item.id);
      for (var r in replies) {
        final fallbackName = (r.ownerUsername ?? '').trim();
        try {
          final user = await UsersRepository().getById(r.ownerId);
          final resolved = (user?.username ?? fallbackName).trim();
          _replyOwnerNames[r.id] = resolved.isEmpty ? 'Unknown' : resolved;
          _replyOwners[r.id] = user;
        } catch (_) {
          _replyOwnerNames[r.id] = fallbackName.isEmpty
              ? 'Unknown'
              : fallbackName;
          _replyOwners[r.id] = null;
        }
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
    try {
      final count = await FavouriteRepository().getFavouriteCount(_item.id);
      if (mounted) {
        setState(() {
          _favCount = count;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _favCount = null;
        });
      }
    }
  }

  Future<void> _openPurchaseCheckout() async {
    if (loginUser == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    if (loginUser!.id == _item.ownerId) {
      if (!mounted) {
        return;
      }
      AppSnackBars.success(
        context,
        'This is your own listing, so you cannot buy it.',
      );
      return;
    }
    if (_item.price == null) {
      if (!mounted) return;
      AppSnackBars.warning(context, 'This listing has no purchase price.');
      return;
    }

    final meetups = MeetupAddressOption.fromSellerItem(_item);
    final sellerName = _owner!.username.trim().isEmpty
        ? 'Seller'
        : _owner!.username;
    final sellerId = _item.ownerId;
    if (sellerId == null || sellerId.isEmpty) {
      if (!mounted) return;
      AppSnackBars.error(context, 'Seller account id not found.');
      return;
    }

    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          flowKind: CheckoutFlowKind.purchase,
          primaryItem: _item,
          sellerDisplayName: sellerName,
          sellerId: sellerId,
          buyerId: loginUser!.id,
          sellerMeetupOptions: meetups,
        ),
      ),
    );

    if (completed == true) {
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    }
  }

  ImageProvider? _resolveAvatarImage(String? imagePath) {
    if (imagePath == null) return null;
    final trimmed = imagePath.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http')) {
      return NetworkImage(trimmed);
    }
    if (trimmed.startsWith('assets/')) {
      return AssetImage(trimmed);
    }
    return FileImage(File(trimmed));
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
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 50),
      );
    }
    return Image.file(
      File(url),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image, size: 50),
    );
  }

  Future<void> _toggleFavourite() async {
    if (loginUser == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final previousState = _isFavourite;
    final previousCount = _favCount ?? 0;

    if (!mounted) return;

    try {
      await ItemService().toggleFavourite(_item.id, loginUser!.id);

      setState(() {
        _isFavourite = !previousState;
        _item.isFavorite = _isFavourite;

        final nextCount = _isFavourite ? previousCount + 1 : previousCount - 1;

        _favCount = nextCount < 0 ? 0 : nextCount;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isFavourite = previousState;
        _item.isFavorite = previousState;
        _favCount = previousCount;
      });

      log("Favourite error: $e");

      AppSnackBars.error(
        context,
        'Failed to update favourite. Please try again.',
      );
    }
  }

  Future<void> _refreshItemDetails() async {
    final refreshedItem = await ItemsRepository().getById(_item.id);
    final refreshedReplies = await ItemsRepository().getReplyList(_item.id);
    if (!mounted || refreshedItem == null) return;
    setState(() {
      _item = refreshedItem;
      _isFavourite = refreshedItem.isFavorite;
      _replies = refreshedReplies;
    });
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
      await ItemsRepository().dropListing(_item.id);

      for (var r in _replies) {
        if (r.status == 'pending') {
          await ItemsRepository().updateStatus('rejected', r.id);
        }
      }

      if (mounted) {
        AppSnackBars.success(context, 'Listing dropped successfully');
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
          AppSnackBars.success(context, 'Offer dropped successfully');
          _fetchReplies();
        }
      } catch (e) {
        if (mounted) {
          AppSnackBars.error(
            context,
            'Could not remove this trade offer right now. Please try again.',
          );
        }
        log("Error dropping offer: $e");
      }
    }
  }

  Future<void> _acceptReply(int replyId) async {
    final actingOwner = widget.loginUser;
    if (actingOwner == null) {
      return;
    }

    ItemListing? acceptedReply;
    for (var r in _replies) {
      if (r.id == replyId) {
        acceptedReply = r;
        await ItemsRepository().updateStatus('accepted', r.id);
      } else if (r.status != 'dropped') {
        await ItemsRepository().updateStatus('rejected', r.id);
      }
    }
    await ItemsRepository().updateStatus('reserved', _item.id);

    if (acceptedReply != null) {
      Transaction? createdTx;
      try {
        createdTx = await TransactionsRepository().create(
          Transaction(
            transactionId: 0,
            buyerId: acceptedReply.ownerId,
            sellerId: _item.ownerId,
            itemId: _item.id,
            tradedItemId: acceptedReply.id,
            transactionType: 'trade',
            transactionStatus: 'pending',
            itemPrice: null,
            shippingFee: 0,
            totalAmount: 0,
            fulfillmentMethod: 'meetup',
            address: null,
            cancelledBy: null,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
      } catch (e) {
        if (mounted) {
          AppSnackBars.error(
            context,
            'Offer accepted, but we could not create the transaction yet. Please try again.',
          );
        }
      }

      final ownerName = actingOwner.username.trim().isNotEmpty
          ? actingOwner.username.trim()
          : (_owner!.username.trim().isNotEmpty
                ? _owner!.username.trim()
                : 'Item owner');
      final offerImage = acceptedReply.imageUrls.isNotEmpty
          ? acceptedReply.imageUrls.first
          : null;

      try {
        final chat = await _chatService.createOrGetItemChat(
          otherUserId: acceptedReply.ownerId,
          itemId: _item.id,
        );
        // Send as media message with image (left-aligned bubble with item link)
        final caption = StringBuffer()
          ..writeln('I accepted your trade offer for "${_item.name}".')
          ..writeln('Offered item: "${acceptedReply.name}"');
        final autoMessagePayload = <String, dynamic>{
          'type': 'image',
          'url': offerImage ?? '',
          'caption': caption.toString().trim(),
          'item_id': _item.id,
          'offered_item_id': acceptedReply.id,
          if (createdTx != null) 'transaction_id': createdTx.transactionId,
          'buyer_id': acceptedReply.ownerId,
          'seller_id': _item.ownerId,
        };
        final autoMessage = '[[media]]${jsonEncode(autoMessagePayload)}';

        await _chatService.sendMessage(chatId: chat.id, content: autoMessage);

        await NotificationService.instance.sendNotificationToUser(
          recipientId: acceptedReply.ownerId,
          title: 'Trade Offer Accepted',
          body: '$ownerName accepted your trade offer on "${_item.name}".',
          type: 'trade',
          data: {
            'action': 'open_item',
            'item_id': _item.id,
            'offered_item_id': acceptedReply.id,
            'chat_id': chat.id,
            if (createdTx != null) 'transaction_id': createdTx.transactionId,
          },
        );
      } catch (e) {
        if (mounted) {
          AppSnackBars.error(
            context,
            'Offer accepted, but we could not send the chat/notification update.',
          );
        }
      }
    }

    await _fetchReplies();

    await _refreshItemDetails();
  }

  Future<void> _rejectReply(int replyId) async {
    ItemListing? rejectedReply;
    for (final reply in _replies) {
      if (reply.id == replyId) {
        rejectedReply = reply;
        break;
      }
    }

    await ItemsRepository().updateStatus('rejected', replyId);

    if (rejectedReply != null && loginUser != null) {
      final ownerName = loginUser!.username.trim().isNotEmpty
          ? loginUser!.username.trim()
          : (_owner!.username.trim().isNotEmpty
                ? _owner!.username.trim()
                : 'Item owner');
      try {
        await NotificationService.instance.sendNotificationToUser(
          recipientId: rejectedReply.ownerId,
          title: 'Trade Offer Rejected',
          body: '$ownerName rejected your trade offer on "${_item.name}".',
          type: 'trade',
          data: {
            'action': 'open_item',
            'item_id': _item.id,
            'offered_item_id': rejectedReply.id,
          },
        );
      } catch (e) {
        if (mounted) {
          AppSnackBars.error(
            context,
            'Offer rejected, but we could not send the notification update.',
          );
        }
      }
    }

    await _fetchReplies();
  }

  Future<void> _composeAndStartItemConversation() async {
    final currentUser = loginUser;

    if (currentUser == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    if (currentUser.id == _item.ownerId) {
      if (!mounted) return;
      AppSnackBars.info(context, 'You cannot start chat on your own item.');
      return;
    }

    final ownerName = _owner!.username.trim().isEmpty
        ? 'there'
        : _owner!.username.trim();
    final initialMessage =
        'Hi $ownerName, I\'m interested in your "${_item.name}". Is it still available?';
    var draftMessage = initialMessage;

    final shouldSend =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  final canSend = draftMessage.trim().isNotEmpty;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE9D8FF)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Start conversation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5B21B6),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F1FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE3D2FF)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: _item.imageUrls.isNotEmpty
                                      ? _buildImage(
                                          _item.imageUrls.first,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: const Color(0xFFE9D8FF),
                                          child: const Icon(
                                            Icons.inventory_2_rounded,
                                            color: Color(0xFF6F45FF),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF3F267A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'To: ${_owner!.username.isEmpty ? 'Item owner' : _owner!.username}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF7868A8),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _item.listingType.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9060FF),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: draftMessage,
                          maxLines: 4,
                          minLines: 3,
                          autofocus: true,
                          onChanged: (value) {
                            draftMessage = value;
                            setSheetState(() {});
                          },
                          decoration: InputDecoration(
                            hintText: 'Write your first message...',
                            filled: true,
                            fillColor: const Color(0xFFFCFAFF),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFDCC9FF),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFDCC9FF),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF8B5DFF),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: canSend
                                    ? () => Navigator.of(context).pop(true)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6F45FF),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Send'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ) ??
        false;

    final message = draftMessage.trim();

    if (!shouldSend || message.isEmpty) {
      return;
    }

    try {
      final chat = await _chatService.createOrGetItemChat(
        otherUserId: _item.ownerId,
        itemId: _item.id,
      );
      await _chatService.sendMessage(chatId: chat.id, content: message);
      await NotificationService.instance.sendSystemNotification(
        title: 'Message Sent',
        body:
            'Your message to ${_owner!.username.isEmpty ? 'the owner' : _owner!.username} has been delivered.',
        type: 'chat',
      );
      if (!mounted) {
        return;
      }

      AppSnackBars.info(
        context,
        'Message sent to ${_owner!.username.isEmpty ? 'owner' : _owner!.username}. Open Inbox to continue chatting.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      final errorText = e.toString();
      String message =
          'Unable to start conversation right now. Please try again.';
      if (errorText.contains('23505')) {
        message =
            'Conversation already exists with this user. Please open Inbox to continue chatting.';
      } else if (errorText.contains('PGRST202')) {
        message = 'Chat service is syncing. Please try again in a moment.';
      } else if (errorText.contains('22P02')) {
        message =
            'Item information is not ready yet. Please refresh and try again.';
      }
      AppSnackBars.error(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final loginUser = widget.loginUser;
    final owner = _owner;
    final fallbackOwnerName = (_item.ownerUsername ?? '').trim();
    final ownerName = (owner?.username ?? fallbackOwnerName).trim().isEmpty
        ? 'Item owner'
        : (owner?.username ?? fallbackOwnerName).trim();
    final ownerAvatar = _resolveAvatarImage(owner?.profileImage);
    const accent = Color(0xFF5B21B6);
    const accentSoft = Color(0xFFF3E8FF);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ProfileScreen(viewingUserId: item.ownerId),
                  ),
                ).then((_) {
                  if (mounted) _loadFollowState();
                });
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: ownerAvatar,
                    child: ownerAvatar == null
                        ? const Icon(Icons.person, size: 16)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                    child: Text(ownerName, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            if (loginUser == null || loginUser.id != item.ownerId)
              TextButton(
                onPressed: _isLoadingFollow
                    ? null
                    : () async {
                        final targetUserId = item.ownerId;

                        if (loginUser == null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                          return;
                        }

                        if (loginUser.id == targetUserId) {
                          if (!mounted) return;
                          AppSnackBars.error(context, 'You cannot follow yourself.');
                          return;
                        }

                        setState(() => _isLoadingFollow = true);

                        try {
                          if (_isFollowing) {
                            await FollowService.unfollowUser(
                              loginUser.id,
                              targetUserId,
                            );
                            setState(() => _isFollowing = false);
                          } else {
                            await FollowService.followUser(
                              loginUser.id,
                              targetUserId,
                            );
                            setState(() => _isFollowing = true);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            _isFollowing
                                ? AppSnackBars.success(
                                    context,
                                    'Following now!',
                                  )
                                : AppSnackBars.success(
                                    context,
                                    'Unfollowed successfully.',
                                  );
                          }
                        } catch (e) {
                          print('Follow error: $e');
                          if (!mounted) return;

                          if (mounted)
                            AppSnackBars.error(context, 'Could not update follow status right now. Please try again.');
                        } finally {
                          if (mounted) setState(() => _isLoadingFollow = false);
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
          if (item.repliedTo == null)
            IconButton(
              icon: const Icon(Icons.chat, color: Color(0xFF5B21B6)),
              onPressed: _composeAndStartItemConversation,
              tooltip: 'Start Conversation',
              padding: EdgeInsets.symmetric(horizontal: 5),
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
                  if (_item.repliedTo == null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _toggleFavourite,
                          icon: Icon(
                            _isFavourite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _isFavourite
                                ? Colors.red
                                : Color(0xFF5B21B6),
                            size: 28,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        if (_favCount != null) ...[
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
                        color:
                            item.status == 'available' ||
                                item.status == 'pending'
                            ? Color(0xFFE6FEE1)
                            : item.status == 'dropped'
                            ? Color(0xFFFFC0C4)
                            : Color(0xFFF2ECFF),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            item.status == 'available' ||
                                item.status == 'pending'
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
                                color:
                                    item.status == 'available' ||
                                        item.status == 'pending'
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
                                color:
                                    item.status == 'available' ||
                                        item.status == 'pending'
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
              if (item.repliedTo == null && item.listingType != 'sell')
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
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                              item.latitude!,
                              item.longitude!,
                            ),
                            initialZoom: 15,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                              userAgentPackageName: "com.example.swaply",
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(
                                    item.latitude!,
                                    item.longitude!,
                                  ),
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_pin,
                                    color: Colors.red,
                                    size: 40,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    if (item.address != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.grey,
                          ),
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
              if (item.listingType != 'sell' && item.repliedTo == null)
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
                if (reply.status == 'dropped' &&
                    reply.ownerId != loginUser?.id) {
                  return Container();
                }
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ItemDetailsScreen(
                          loginUser: loginUser,
                          item: reply,
                        ),
                      ),
                    );
                  },
                  child: Container(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                  fontSize: 18,
                                                  color: Color(0xFF5B21B6),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ProfileScreen(
                                                    viewingUserId:
                                                        reply.ownerId,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Builder(
                                              builder: (context) {
                                                final replyOwner =
                                                    _replyOwners[reply.id];
                                                final replyAvatar =
                                                    _resolveAvatarImage(
                                                      replyOwner?.profileImage,
                                                    );
                                                return CircleAvatar(
                                                  radius: 12,
                                                  backgroundImage: replyAvatar,
                                                  child: replyAvatar == null
                                                      ? const Icon(
                                                          Icons.person,
                                                          size: 12,
                                                        )
                                                      : null,
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    0,
                                                    0,
                                                    16,
                                                    0,
                                                  ),
                                              child: Text(
                                                _replyOwnerNames[reply.id]!,
                                                style: const TextStyle(
                                                  fontSize: 16,
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
                                        if (loginUser != null &&
                                            loginUser.id == item.ownerId &&
                                            reply.status == 'pending')
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextButton(
                                                  onPressed: () {
                                                    _acceptReply(reply.id);
                                                  },
                                                  style: TextButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF5B21B6),
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
                                                    backgroundColor:
                                                        const Color(0xFFE9E1FE),
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
                        if (loginUser != null &&
                            loginUser.id == reply.ownerId &&
                            reply.status == 'pending')
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _dropReply(reply.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 14),
              if (item.status == 'available' || item.status == 'pending') ...[
                if (loginUser != null && loginUser.id == item.ownerId)
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreateItemScreen(
                                  user: loginUser,
                                  item: item,
                                ),
                              ),
                            );
                            if (result == true && mounted) {
                              await _refreshItemDetails();
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
                  if (item.repliedTo == null && item.listingType == 'both')
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              if (loginUser == null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginScreen(),
                                  ),
                                );
                                return;
                              } else {
                                _openPurchaseCheckout();
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
                              'Buy Now',
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
                            onPressed: () async {
                              if (loginUser == null) {
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
                                    user: loginUser,
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
                  else if (item.repliedTo == null && item.listingType == 'sell')
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          if (loginUser == null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                            return;
                          } else {
                            _openPurchaseCheckout();
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
                          'Buy Now',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    )
                  else if (item.repliedTo == null &&
                      item.listingType == 'trade')
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () async {
                          if (loginUser == null) {
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
                                user: loginUser,
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
      case 'available':
      case 'accepted':
      case 'confirmed':
        color = Colors.green;
        break;
      case 'dropped':
      case 'rejected':
        color = Colors.red;
        break;
      case 'reserved':
        color = Colors.orange;
        break;
      case 'pending':
        color = Colors.grey[400]!;
        break;
      default:
        color = Colors.blue;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
