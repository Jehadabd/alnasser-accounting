class Category {
  final int? id;
  final String name;
  final int? parentId; // For hierarchical categories (e.g., Meat -> Chicken)
  final String? description;

  Category({
    this.id,
    required this.name,
    this.parentId,
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'description': description,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      parentId: map['parent_id'] as int?,
      description: map['description'] as String?,
    );
  }

  Category copyWith({
    int? id,
    String? name,
    int? parentId,
    String? description,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      description: description ?? this.description,
    );
  }
}
