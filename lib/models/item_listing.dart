import '../core/utils/parsing.dart';

class ItemListing {
  final int id;
  final String name;
  final String description;
  final double? price;
  final String listingType;
  final int ownerId;
  final String status;
  final String category;
  final List<String> imageUrls;
  final String? preference;
  final int? repliedTo;
  final DateTime createdAt;
  bool isFavorite; // not from db

  ItemListing({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.listingType,
    required this.ownerId,
    required this.status,
    required this.category,
    required this.imageUrls,
    required this.preference,
    this.repliedTo,
    required this.createdAt,
    this.isFavorite = false
  });

  factory ItemListing.fromMap(Map<String, dynamic> map) {
    return ItemListing(
      id: parseInt(map['id'], fieldName: 'items.id'),
      name: parseString(map['name'], fieldName: 'items.name'),
      description: parseString(
        map['description'],
        fieldName: 'items.description',
      ),
      price: parseNullableDouble(map['price'], fieldName: 'items.price'),
      listingType: parseString(
        map['listing_type'],
        fieldName: 'items.listing_type',
      ),
      ownerId: parseInt(map['owner_id'], fieldName: 'items.owner_id'),
      status: parseString(map['status'], fieldName: 'items.status'),
      category: parseString(map['category'], fieldName: 'items.category'),
      imageUrls: List<String>.from(map['image_urls'] ?? []),
      preference: parseString(map['preference'], fieldName: 'items.preference'),
      repliedTo: parseNullableInt(map['replied_to'], fieldName: 'items.replied_to'),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'items.created_at',
      ),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'listing_type': listingType,
      'owner_id': ownerId,
      'status': status,
      'category': category,
      'image_urls': imageUrls,
      'preference': preference,
      'replied_to': repliedTo
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'listing_type': listingType,
      'owner_id': ownerId,
      'status': status,
      'category': category,
      'image_urls': imageUrls,
      'preference': preference,
      'replied_to': repliedTo,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
