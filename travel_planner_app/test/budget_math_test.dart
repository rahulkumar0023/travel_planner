import 'package:flutter_test/flutter_test.dart';
import 'package:travel_planner_app/models/expense.dart';
import 'package:travel_planner_app/utils/budget_math.dart';

Expense e(String c, double a) => Expense(
  id: 'id', tripId: 't', title: 'x', amount: a, category: 'Food',
  date: DateTime(2025,1,1), paidBy: 'You', sharedWith: const ['You'], currency: c,
);

void main() {
  test('spentForTripInBudgetCcy converts each line then sums', () {
    final ratesEUR = {
      'EUR': 1.0, 'USD': 1 / 0.85, 'INR': 1 / 0.0098,
    };
    final list = [e('EUR', 10), e('USD', 10), e('INR', 1000)];
    // 10 EUR + 10*0.85 + 1000*0.0098 = 10 + 8.5 + 9.8 = 28.3
    final v = spentForTripInBudgetCcy(
      expenses: list,
      budgetCurrency: 'EUR',
      ratesForBaseTo: ratesEUR,
    );
    expect(v, 28.30);
  });
}
