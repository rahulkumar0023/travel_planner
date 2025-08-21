// ▶︎ Envelope view-model start
class EnvelopeVM {
  final String id;            // use monthly budget id
  final String name;          // monthly name or "MMM yyyy"
  final String currency;      // monthly currency
  final double planned;       // monthly.amount
  final double spent;         // sum of linked trips' expenses (converted)
  final int colorIndex;       // stable-ish color index
  EnvelopeVM({
    required this.id,
    required this.name,
    required this.currency,
    required this.planned,
    required this.spent,
    required this.colorIndex,
  });
  double get pct => planned <= 0 ? 0.0 : (spent / planned).clamp(0.0, 1.0);
}
// Envelope view-model end

// ▶︎ MonthlyBudgetSummary start
class MonthlyBudgetSummary {
  final String currency;      // summary currency (monthly currency)
  final double totalBudgeted; // sum(planned)
  final double totalSpent;    // trip-linked + monthly expenses
  final double totalIncome;      // salary etc. (in monthly currency)
  final double totalMonthExpenses;

  MonthlyBudgetSummary({
    required this.currency,
    required this.totalBudgeted,
    required this.totalSpent,
    this.totalIncome = 0.0,
    this.totalMonthExpenses = 0.0,
  });
  double get remaining => (totalBudgeted + totalIncome) - totalSpent;
  double get pctSpent => totalBudgeted <= 0 ? 0.0 : (totalSpent / totalBudgeted).clamp(0.0, 1.0);
}
// MonthlyBudgetSummary end

