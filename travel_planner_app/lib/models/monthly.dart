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
  final double totalSpent;    // sum(spent)
  MonthlyBudgetSummary({
    required this.currency,
    required this.totalBudgeted,
    required this.totalSpent,
  });
  double get remaining => (totalBudgeted - totalSpent);
  double get pctSpent => totalBudgeted <= 0 ? 0.0 : (totalSpent / totalBudgeted).clamp(0.0, 1.0);
}
// MonthlyBudgetSummary end

