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
}
