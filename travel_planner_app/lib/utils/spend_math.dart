import '../models/expense.dart';
import '../services/fx_service.dart';

/// Sum amounts per *original* currency from a list of expenses.
Map<String, double> aggregateByCurrency(Iterable<Expense> expenses) {
  final out = <String, double>{};
  for (final e in expenses) {
    final c = (e.currency.isEmpty ? 'EUR' : e.currency).toUpperCase();
    out[c] = (out[c] ?? 0) + e.amount;
  }
  return out;
}

/// Convert a per-currency map into a single total in [baseCurrency].
/// Pass an FX table produced by FxService.loadRates(baseCurrency).
double totalInBase({
  required Map<String, double> byCurrency,
  required String baseCurrency,
  required Map<String, double> ratesForBaseTo,
}) {
  final base = baseCurrency.toUpperCase();
  double sum = 0.0;
  byCurrency.forEach((from, amount) {
    sum += FxService.convert(
      amount: amount,
      from: from.toUpperCase(),
      to: base,
      ratesForBaseTo: ratesForBaseTo,
    );
  });
  return _round2(sum);
}

/// Helper (banker’s rounding not needed here—just 2 dp).
double _round2(double v) => (v * 100).roundToDouble() / 100.0;
