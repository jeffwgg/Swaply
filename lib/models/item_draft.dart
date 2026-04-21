import '../core/utils/parsing.dart';

class ItemDraft {
  int id;
  String? name;
  String? description;
  double? price;
  String? listingType;
  String ownerId;
  String? category;
  List<String>? imageUrls;
  String? preference;
  int? repliedTo;
  final DateTime createdAt;
  String? address;
  double? latitude;
  double? longitude;
  bool isPendingSubmit;

  ItemDraft({
    required this.id,
    this.name,
    this.description,
    this.price,
    this.listingType,
    required this.ownerId,
    this.category,
    this.imageUrls,
    this.preference,
    this.repliedTo,
    required this.createdAt,
    this.address,
    this.latitude,
    this.longitude,
    required this.isPendingSubmit,
  });

  factory ItemDraft.fromMap(Map<String, dynamic> map) {
    return ItemDraft(
      id: parseInt(map['id'], fieldName: 'items.id'),
      name: parseNullableString(map['name'], fieldName: 'items.name'),
      description: parseNullableString(
        map['description'],
        fieldName: 'items.description',
      ),
      price: parseNullableDouble(map['price'], fieldName: 'items.price'),
      listingType: parseNullableString(
        map['listing_type'],
        fieldName: 'items.listing_type',
      ),
      ownerId: parseString(map['owner_id'], fieldName: 'items.owner_id'),
      category: parseNullableString(map['category'], fieldName: 'items.category'),
      imageUrls: List<String>.from(map['image_urls'] ?? []),
      preference: parseNullableString(
        map['preference'],
        fieldName: 'items.preference',
      ),
      repliedTo: parseNullableInt(
        map['replied_to'],
        fieldName: 'items.replied_to',
      ),
      createdAt: parseDateTime(
        map['created_at'],
        fieldName: 'items.created_at',
      ),
      address: parseNullableString(map['address'], fieldName: 'items.address'),
      latitude: parseNullableDouble(
        map['latitude'],
        fieldName: 'items.latitude',
      ),
      longitude: parseNullableDouble(
        map['longitude'],
        fieldName: 'items.longitude',
      ),
      isPendingSubmit: (map['is_pending_upload'] ?? 0) == 1,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'listing_type': listingType,
      'owner_id': ownerId,
      'category': category,
      'image_urls': imageUrls,
      'preference': preference,
      'replied_to': repliedTo,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
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
      'category': category,
      'image_urls': imageUrls,
      'preference': preference,
      'replied_to': repliedTo,
      'created_at': createdAt.toIso8601String(),
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'is_pending_upload': isPendingSubmit ? 1 : 0,
    };
  }
}
