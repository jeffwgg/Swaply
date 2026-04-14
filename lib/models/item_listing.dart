import '../core/utils/parsing.dart';

class ItemListing {
  final String id;
  final String name;
  final String description;
  final double? price;
  final String listingType;
  final int ownerId;
  final String status;
  final String category;
  final String? imageUrl;
  final String preference;
  final DateTime createdAt;

  const ItemListing({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.listingType,
    required this.ownerId,
    required this.status,
    required this.category,
    this.imageUrl,
    required this.preference,
    required this.createdAt,
  });

  factory ItemListing.fromMap(Map<String, dynamic> map) {
    return ItemListing(
      id: parseInt(map['id'], fieldName: 'items.id'),
      title: parseString(map['title'], fieldName: 'items.title'),
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
      imageUrl: parseNullableString(
        map['image_url'],
        fieldName: 'items.image_url',
      ),
      condition: parseString(map['condition'], fieldName: 'items.condition'),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'items.created_at',
      ),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'title': title,
      'description': description,
      'price': price,
      'listing_type': listingType,
      'owner_id': ownerId,
      'status': status,
      'category': category,
      'image_url': imageUrl,
      'condition': condition,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': name,
      'description': description,
      'price': price,
      'listing_type': listingType,
      'owner_id': ownerId,
      'status': status,
      'category': category,
      'image_url': imageUrl,
      'condition': preference,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
