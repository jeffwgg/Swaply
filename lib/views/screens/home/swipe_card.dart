import 'package:flutter/material.dart';
import '../../../models/app_user.dart';
import '../../../models/item_listing.dart';

class SwipeCard extends StatelessWidget {
  final ItemListing item;
  final AppUser? user;

  const SwipeCard({super.key, required this.item, this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 420,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5A2CA0).withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImage(),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Status badge top right
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _buildStatusBadge(),
                  ),
                  // Listing type badge top left
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _buildTypeBadge(),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item name
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Description
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const Spacer(),

                  // Bottom row — price + category
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Category chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          item.category,
                          style: const TextStyle(
                            color: Color(0xFF5A2CA0),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Price (if not trade only)
                      if (item.price != null && item.listingType != 'trade')
                        Text(
                          'RM ${item.price!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF5A2CA0),
                          ),
                        )
                      else if (item.listingType == 'trade')
                        const Row(
                          children: [
                            Icon(Icons.swap_horiz, color: Color(0xFF5A2CA0), size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Trade',
                              style: TextStyle(
                                color: Color(0xFF5A2CA0),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (item.imageUrls.isNotEmpty) {
      final url = item.imageUrls.first;
      if (url.startsWith('http')) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      }
      return Image.asset(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFF3E8FF),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 60,
          color: Color(0xFFD8B4FE),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color bg;
    Color text;
    String label;

    switch (item.status.toLowerCase()) {
      case 'available':
        bg = const Color(0xFFDCFCE7);
        text = const Color(0xFF16A34A);
        label = 'Available';
        break;
      case 'reserved':
        bg = const Color(0xFFFEF9C3);
        text = const Color(0xFFCA8A04);
        label = 'Reserved';
        break;
      default:
        bg = const Color(0xFFF3E8FF);
        text = const Color(0xFF5A2CA0);
        label = item.status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTypeBadge() {
    IconData icon;
    String label;
    Color bg;
    Color fg;

    switch (item.listingType) {
      case 'trade':
        icon = Icons.swap_horiz;
        label = 'Trade';
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0369A1);
        break;
      case 'sell':
        icon = Icons.sell_outlined;
        label = 'Sell';
        bg = const Color(0xFFFEF9C3);
        fg = const Color(0xFFCA8A04);
        break;
      default:
        icon = Icons.swap_horiz;
        label = 'Both';
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF5A2CA0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}