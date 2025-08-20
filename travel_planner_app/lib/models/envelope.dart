enum EnvelopeType { income, expense }

class EnvelopeDef {
  final String id;          // unique id (string)
  final String name;        // e.g., "Groceries" / "Salary"
  final EnvelopeType type;  // income or expense
  final double planned;     // user-planned amount (in monthly currency)
  final String currency;    // ISO (monthly currency; we normalize to Home)
  final String? parentId;   // for subcategories

  EnvelopeDef({
    required this.id,
    required this.name,
    required this.type,
    required this.planned,
    required this.currency,
    this.parentId,
  });

  EnvelopeDef copyWith({
    String? id,
    String? name,
    EnvelopeType? type,
    double? planned,
    String? currency,
    String? parentId,
  }) {
    return EnvelopeDef(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      planned: planned ?? this.planned,
      currency: currency ?? this.currency,
      parentId: parentId ?? this.parentId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'planned': planned,
    'currency': currency,
    'parentId': parentId,
  };

  factory EnvelopeDef.fromJson(Map<String, dynamic> j) => EnvelopeDef(
    id: j['id'] as String,
    name: j['name'] as String,
    type: ((j['type'] as String) == 'income') ? EnvelopeType.income : EnvelopeType.expense,
    planned: (j['planned'] as num).toDouble(),
    currency: (j['currency'] as String).toUpperCase(),
    parentId: j['parentId'] as String?,
  );
}

class EnvelopeSpend {
  final EnvelopeDef def;
  final double spent; // always expressed in monthly currency
  EnvelopeSpend({required this.def, required this.spent});

  double get remaining => (def.planned - spent);
  double get pct => def.planned <= 0 ? 0 : (spent / def.planned).clamp(0, 1);
}

