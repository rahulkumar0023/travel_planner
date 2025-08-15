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
