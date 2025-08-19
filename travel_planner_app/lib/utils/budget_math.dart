import '../models/expense.dart';
import '../services/fx_service.dart';

double spentForTripInBudgetCcy({
  required Iterable<Expense> expenses,
  required String budgetCurrency,
  required Map<String, double> ratesForBaseTo, // budgetCurrency as base
}) {
  double sum = 0.0;
  for (final e in expenses) {
    final from = e.currency.isEmpty ? budgetCurrency : e.currency;
    sum += FxService.convert(
      amount: e.amount,
      from: from,
      to: budgetCurrency,
      ratesForBaseTo: ratesForBaseTo,
    );
  }
  return (sum * 100).roundToDouble() / 100.0;
}
