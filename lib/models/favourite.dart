class Favourite {
  final int? id;
  final String userId;
  final int itemId;
  final DateTime? createdAt;

  Favourite({
    this.id,
    required this.userId,
    required this.itemId,
    this.createdAt,
  });

  factory Favourite.fromJson(Map<String, dynamic> json) {
    return Favourite(
      id: json['id'],
      userId: json['user_id'],
      itemId: json['item_id'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'item_id': itemId,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
