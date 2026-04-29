import 'item_listing.dart';

class MeetupAddressOption {
  final String id;
  final String label;
  final String fullAddress;

  const MeetupAddressOption({
    required this.id,
    required this.label,
    required this.fullAddress,
  });

  /// Uses the listing's [ItemListing.address] when the seller saved one.
  static List<MeetupAddressOption> fromSellerItem(ItemListing item) {
    final trimmed = item.address?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return const [];
    }
    return [
      MeetupAddressOption(
        id: 'seller_listed',
        label: "Seller's preferred meet-up",
        fullAddress: trimmed,
      ),
    ];
  }

  /// Trade helper: include seller item address and offered item address (if any).
  /// This matches the UX expectation that either party's saved address can be used
  /// as a meet-up starting point.
  static List<MeetupAddressOption> fromTradeItems({
    required ItemListing sellerItem,
    required ItemListing offeredItem,
  }) {
    final sellerAddr = sellerItem.address?.trim();
    final buyerAddr = offeredItem.address?.trim();

    final options = <MeetupAddressOption>[];
    if (sellerAddr != null && sellerAddr.isNotEmpty) {
      options.add(
        MeetupAddressOption(
          id: 'seller_listed',
          label: "Seller's address",
          fullAddress: sellerAddr,
        ),
      );
    }
    if (buyerAddr != null &&
        buyerAddr.isNotEmpty &&
        (sellerAddr == null || sellerAddr.isEmpty || buyerAddr != sellerAddr)) {
      options.add(
        MeetupAddressOption(
          id: 'buyer_listed',
          label: "Buyer's address",
          fullAddress: buyerAddr,
        ),
      );
    }
    return options;
  }
}
