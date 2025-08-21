// ===== monthly_category.dart — START =====
// Description: Model for Monthly Categories with optional sub-categories.

enum MonthlyKind { income, expense }

class MonthlySubCategory {
  final String id;
  final String name;
  final double planned;


  // 👇 add here
  String get type {
    if (name.toLowerCase().contains('salary') ||
        name.toLowerCase().contains('income')) {
      return 'income';
    }
    return 'expense';
  }


  MonthlySubCategory({required this.id, required this.name, this.planned = 0.0});

  factory MonthlySubCategory.fromJson(Map<String, dynamic> json) =>
      MonthlySubCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        planned: (json['planned'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'planned': planned};

  MonthlySubCategory copyWith({String? id, String? name, double? planned}) =>
      MonthlySubCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        planned: planned ?? this.planned,
      );
}

typedef MonthlySubcategory = MonthlySubCategory;

class MonthlyCategory {
  final String id;
  final String name;
  final MonthlyKind kind;
  final List<MonthlySubCategory> subs;
  final String? parentId;

  MonthlyCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.subs,
    this.parentId,
  });

  MonthlyCategory copyWith({
    String? id,
    String? name,
    MonthlyKind? kind,
    List<MonthlySubCategory>? subs,
    String? parentId,
  }) =>
      MonthlyCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        subs: subs ?? this.subs,
        parentId: parentId ?? this.parentId,
      );

  factory MonthlyCategory.fromJson(Map<String, dynamic> json) => MonthlyCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: MonthlyKind.values.firstWhere(
            (k) =>
                k.name ==
                (json['type'] as String? ?? json['kind'] as String? ?? 'expense'),
            orElse: () => MonthlyKind.expense),
        subs: (json['subs'] as List? ?? [])
            .map((e) => MonthlySubCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
        parentId: json['parentId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': kind.name,
        'subs': subs.map((e) => e.toJson()).toList(),
        if (parentId != null) 'parentId': parentId,
      };
}
// ===== monthly_category.dart — END =====
