class MonthlyBudgetSummary {
  final String currency;
  final double totalBudgeted;
  final double totalSpent;
  double get remaining => (totalBudgeted - totalSpent);
  double get pctSpent => totalBudgeted <= 0 ? 0 : (totalSpent / totalBudgeted);

  const MonthlyBudgetSummary({
    required this.currency,
    required this.totalBudgeted,
    required this.totalSpent,
  });

  factory MonthlyBudgetSummary.fromJson(Map<String, dynamic> j) => MonthlyBudgetSummary(
    currency: (j['currency'] ?? 'EUR') as String,
    totalBudgeted: (j['totalBudgeted'] as num).toDouble(),
    totalSpent: (j['totalSpent'] as num).toDouble(),
  );
}

class MonthlyCategory {
  final String id;
  final String name;
  final String currency;
  final double planned; // budgeted
  final double spent;   // aggregated
  final int colorIndex;
  double get pct => planned <= 0 ? 0 : (spent / planned).clamp(0, 1);

  const MonthlyCategory({
    required this.id,
    required this.name,
    required this.currency,
    required this.planned,
    required this.spent,
    this.colorIndex = 0,
  });

  factory MonthlyCategory.fromJson(Map<String, dynamic> j) => MonthlyCategory(
    id: j['id'] as String,
    name: j['name'] as String,
    currency: (j['currency'] ?? 'EUR') as String,
    planned: (j['planned'] as num).toDouble(),
    spent: (j['spent'] as num).toDouble(),
    colorIndex: (j['colorIndex'] ?? 0) as int,
  );
}
