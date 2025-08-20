import 'package:hive/hive.dart';
import '../models/expense.dart';
import '../models/monthly_category.dart';
import '../services/api_service.dart';

class MonthlyTotals {
  final double planned;
  final double spent;
  final String currency;
  MonthlyTotals({required this.planned, required this.spent, required this.currency});
  double get remaining => (planned - spent);
  double get pct => planned <= 0 ? 0 : (spent / planned).clamp(0, 1);
}

/// Sums planned (from envelopes) and spent (from local expenses) for the month.
/// NOTE: Spent is summed by matching expense.category to subcategory name.
///       Cross-currency conversion can be added with ApiService.convert(...).
Future<MonthlyTotals> computeTotals({
  required DateTime month,
  required List<MonthlyCategory> envelopes,
  required String monthlyCurrency,
  required ApiService api,
}) async {
  final box = Hive.box<Expense>('expensesBox');
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);

  // Planned = sum of all sub planned in monthlyCurrency
  final planned = envelopes.fold<double>(0, (p, c) =>
      p + c.subs.fold<double>(0, (pp, s) => pp + s.planned));

  // Spent = sum of expenses in the month, mapped to envelopes by name
  double spent = 0;
  for (final e in box.values) {
    final d = e.date;
    if (d.isBefore(start) || !d.isBefore(end)) continue;

    // match by sub name first (exact), then by category name → put into first sub
    final lower = e.category.trim().toLowerCase();
    MonthlyCategory? cat;
    MonthlySubcategory? sub;
    for (final c in envelopes) {
      for (final s in c.subs) {
        if (s.name.trim().toLowerCase() == lower) {
          cat = c;
          sub = s;
          break;
        }
      }
      if (cat != null) break;
    }
    cat ??= envelopes.firstWhere(
      (c) => c.name.trim().toLowerCase() == lower,
      orElse: () => envelopes.isEmpty ? null as MonthlyCategory : envelopes.first,
    );
    if (cat == null) continue;

    // currency conversion (TODO: use api.convert if different)
    final from = e.currency.toUpperCase();
    final to = monthlyCurrency.toUpperCase();
    final value = (from == to)
        ? e.amount
        : await api.convert(amount: e.amount, from: from, to: to);

    // Income reduces “spent” (spent can be negative → more left over)
    if (cat.kind == MonthlyKind.income) {
      spent -= value;
    } else {
      spent += value;
    }
  }

  return MonthlyTotals(planned: planned, spent: spent, currency: monthlyCurrency);
}
