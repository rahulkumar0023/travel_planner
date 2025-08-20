class MonthlySubcategory {
  final String id;
  final String name;
  final double planned; // planned amount for the month
  MonthlySubcategory({
    required this.id,
    required this.name,
    this.planned = 0,
  });

  MonthlySubcategory copyWith({String? id, String? name, double? planned}) =>
      MonthlySubcategory(
        id: id ?? this.id,
        name: name ?? this.name,
        planned: planned ?? this.planned,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'planned': planned,
      };
  factory MonthlySubcategory.fromJson(Map<String, dynamic> j) =>
      MonthlySubcategory(
        id: j['id'] as String,
        name: j['name'] as String,
        planned: (j['planned'] as num?)?.toDouble() ?? 0,
      );
}

enum MonthlyKind { income, expense }

class MonthlyCategory {
  final String id;
  final MonthlyKind kind;
  final String name; // e.g. “Food”, “Salary”
  final String currency; // envelope currency (usually your monthly base)
  final List<MonthlySubcategory> subs;

  MonthlyCategory({
    required this.id,
    required this.kind,
    required this.name,
    required this.currency,
    this.subs = const [],
  });

  MonthlyCategory copyWith({
    String? id,
    MonthlyKind? kind,
    String? name,
    String? currency,
    List<MonthlySubcategory>? subs,
  }) =>
      MonthlyCategory(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        currency: currency ?? this.currency,
        subs: subs ?? this.subs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'currency': currency,
        'subs': subs.map((s) => s.toJson()).toList(),
      };

  factory MonthlyCategory.fromJson(Map<String, dynamic> j) => MonthlyCategory(
        id: j['id'] as String,
        kind: (j['kind'] as String) == 'income'
            ? MonthlyKind.income
            : MonthlyKind.expense,
        name: j['name'] as String,
        currency: (j['currency'] as String?) ?? 'EUR',
        subs: ((j['subs'] as List?) ?? const [])
            .map((e) => MonthlySubcategory.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
