enum CategoryType { income, expense }

class CategoryItem {
  final String id; // e.g. 'exp-food', 'inc-salary', 'exp-food-coffee'
  final String name; // display name
  final CategoryType type; // income | expense
  final String? parentId; // null => top-level category; else subcategory of parent
  final int colorIndex; // for consistent color chips in UI

  const CategoryItem({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
    this.colorIndex = 0,
  });

  bool get isRoot => parentId == null;

  CategoryItem copyWith({
    String? id,
    String? name,
    CategoryType? type,
    String? parentId,
    int? colorIndex,
  }) => CategoryItem(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    parentId: parentId ?? this.parentId,
    colorIndex: colorIndex ?? this.colorIndex,
  );

  // JSON
  factory CategoryItem.fromJson(Map<String, dynamic> j) => CategoryItem(
        id: j['id'],
        name: j['name'],
        type: (j['type'] == 'income') ? CategoryType.income : CategoryType.expense,
        parentId: j['parentId'],
        colorIndex: (j['colorIndex'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type == CategoryType.income ? 'income' : 'expense',
        'parentId': parentId,
        'colorIndex': colorIndex,
      };
}
