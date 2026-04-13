class ItemListing {
  final String id;
  final String name;
  final String description;
  final double? price;
  final String listingType;
  final String ownerId;
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
      id: map['id'] as String,
      name: map['title'] as String,
      description: map['description'] as String,
      price: (map['price'] as num?)?.toDouble(),
      listingType: map['listing_type'] as String,
      ownerId: map['owner_id'] as String,
      status: map['status'] as String,
      category: map['category'] as String,
      imageUrl: map['image_url'] as String?,
      preference: map['condition'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
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
