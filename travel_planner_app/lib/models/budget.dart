enum BudgetKind { monthly, trip }

class Budget {
  final String id;
  final BudgetKind kind;
  final String currency;
  final double amount;

  // For monthly
  final int? year;
  final int? month;

  // For trip budgets
  final String? tripId;
  final String? name;

  // Linking (trip → monthly)
  final String? linkedMonthlyBudgetId;

  Budget({
    required this.id,
    required this.kind,
    required this.currency,
    required this.amount,
    this.year,
    this.month,
    this.tripId,
    this.name,
    this.linkedMonthlyBudgetId,
  });

  // --- add this ---
  static const _noChange = Object();

  Budget copyWith({
    String? id,
    BudgetKind? kind,
    String? currency,
    double? amount,
    int? year,
    int? month,
    String? tripId,
    String? name,
    // Use the sentinel so you can *set* null intentionally:
    Object? linkedMonthlyBudgetId = _noChange,
  }) {
    return Budget(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      currency: currency ?? this.currency,
      amount: amount ?? this.amount,
      year: year ?? this.year,
      month: month ?? this.month,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
      linkedMonthlyBudgetId: identical(linkedMonthlyBudgetId, _noChange)
          ? this.linkedMonthlyBudgetId
          : linkedMonthlyBudgetId as String?,
    );
  }
  // --- end add ---

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
    id: j['id'].toString(),
    kind: (j['kind'] ?? 'trip') == 'monthly' ? BudgetKind.monthly : BudgetKind.trip,
    currency: j['currency'] ?? 'EUR',
    amount: (j['amount'] as num).toDouble(),
    year: j['year'],
    month: j['month'],
    tripId: j['tripId'],
    name: j['name'],
    linkedMonthlyBudgetId: j['linkedMonthlyBudgetId'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind == BudgetKind.monthly ? 'monthly' : 'trip',
    'currency': currency,
    'amount': amount,
    if (year != null) 'year': year,
    if (month != null) 'month': month,
    if (tripId != null) 'tripId': tripId,
    if (name != null) 'name': name,
    if (linkedMonthlyBudgetId != null) 'linkedMonthlyBudgetId': linkedMonthlyBudgetId,
  };
}
