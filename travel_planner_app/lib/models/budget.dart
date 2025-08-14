class Budget {
  final String id;
  final String name;
  final String currency; // e.g. "EUR"
  final double planned; // amountLimit
  final double spent; // spent in budget.currency
  final double? spentInHome; // optional: converted in home currency
  final int colorIndex; // for avatar stripe or progress color

  Budget({
    required this.id,
    required this.name,
    required this.currency,
    required this.planned,
    required this.spent,
    this.spentInHome,
    this.colorIndex = 0,
  });

  double get pct => planned <= 0 ? 0 : (spent / planned).clamp(0, 1);
}

// An aggregate for the header ring
class MonthlyBudgetSummary {
  final DateTime month; // e.g., 2025-08-01
  final String currency; // display/base currency for header
  final double initialBalance; // optional
  final double totalBudgeted;
  final double totalSpent;
  final double remaining;

  MonthlyBudgetSummary({
    required this.month,
    required this.currency,
    required this.initialBalance,
    required this.totalBudgeted,
    required this.totalSpent,
    required this.remaining,
  });

  double get pctSpent =>
      totalBudgeted <= 0 ? 0 : (totalSpent / totalBudgeted).clamp(0, 1);
}

