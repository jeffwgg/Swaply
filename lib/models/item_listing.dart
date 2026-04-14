import '../core/utils/parsing.dart';

class ItemListing {
  final int id;
  final String title;
  final String description;
  final double? price;
  final String listingType;
  final int ownerId;
  final String status;
  final String category;
  final String? imageUrl;
  final String condition;
  final DateTime createdAt;

  const ItemListing({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.listingType,
    required this.ownerId,
    required this.status,
    required this.category,
    this.imageUrl,
    required this.condition,
    required this.createdAt,
  });

  factory ItemListing.fromMap(Map<String, dynamic> map) {
    DateTime parseDateTime(dynamic value) {
      if (value is DateTime) {
        return value;
      }
      return DateTime.parse(value as String);
    }

    return ItemListing(
      id: parseInt(map['id'], fieldName: 'items.id'),
      title: map['title'] as String,
      description: map['description'] as String,
      price: (map['price'] as num?)?.toDouble(),
      listingType: map['listing_type'] as String,
      ownerId: parseInt(map['owner_id'], fieldName: 'items.owner_id'),
      status: map['status'] as String,
      category: map['category'] as String,
      imageUrl: map['image_url'] as String?,
      condition: map['condition'] as String,
      createdAt: parseDateTime(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'listing_type': listingType,
      'owner_id': ownerId,
      'status': status,
      'category': category,
      'image_url': imageUrl,
      'condition': condition,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
