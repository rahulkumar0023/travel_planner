// monthly.dart start
// 👇 NEW: Monthly overview + envelopes data models
class MonthlyBudgetSummary {
  final String currency;        // e.g., 'EUR'
  final double totalBudgeted;   // sum of all monthly budgets (in their own ccy converted to currency)
  final double totalSpent;      // sum of linked trip spends converted to currency
  final double remaining;       // totalBudgeted - totalSpent
  final double pctSpent;        // clamp 0..1

  const MonthlyBudgetSummary({
    required this.currency,
    required this.totalBudgeted,
    required this.totalSpent,
    required this.remaining,
    required this.pctSpent,
  });
}

class MonthlyEnvelope {
  final String id;              // stable id (can reuse budget id)
  final String name;            // e.g., 'Food' or 'Income: Salary'
  final String currency;        // envelope currency (usually same as monthly currency)
  final double planned;         // budgeted amount
  final double spent;           // computed spent
  final int colorIndex;         // for row color variation
  final List<MonthlyEnvelope> children; // optional sub-categories

  const MonthlyEnvelope({
    required this.id,
    required this.name,
    required this.currency,
    required this.planned,
    required this.spent,
    this.colorIndex = 0,
    this.children = const <MonthlyEnvelope>[],
  });

  double get pct {
    if (planned <= 0) return 0;
    final p = spent / planned;
    if (p < 0) return 0;
    if (p > 1.0) return 1.0;
    return p;
  }
}
// monthly.dart end
