import 'package:flutter_test/flutter_test.dart';
import 'package:travel_planner_app/models/expense.dart';
import 'package:travel_planner_app/utils/spend_math.dart';

// A tiny helper to build expenses quickly.
Expense exp(String c, double a) => Expense(
  id: 'x',
  tripId: 't',
  title: 't',
  amount: a,
  category: 'Food',
  date: DateTime(2025, 8, 19),
  paidBy: 'You',
  sharedWith: const ['You'],
  currency: c,
);

// Fixed EUR-base table (values are units of each currency per EUR)
final eurRates = <String, double>{
  'EUR': 1.0,
  'USD': 1 / 0.85,     // 1 EUR = 1.176470588 USD
  'INR': 1 / 0.0098,   // 1 EUR = 102.0408163265 INR
  'PLN': 1 / 0.235,    // 1 EUR = 4.2553191489 PLN
  'JPY': 1 / 0.006,    // 1 EUR = 166.666666667 JPY
  'AUD': 1 / 0.5577,   // 1 EUR = 1.7930787162 AUD
};

void main() {
  group('spend_math', () {
    test('aggregateByCurrency sums correctly', () {
      final list = <Expense>[
        exp('EUR', 50),
        exp('INR', 2000),
        exp('EUR', 10),
        exp('usd', 3), // lower-case should be handled
      ];
      final agg = aggregateByCurrency(list);

      expect(agg['EUR'], closeTo(60.0, 1e-9));
      expect(agg['INR'], closeTo(2000.0, 1e-9));
      expect(agg['USD'], closeTo(3.0, 1e-9));
      expect(agg.keys.length, 3);
    });

    test('totalInBase converts all to base using provided table', () {
      final by = <String, double>{'EUR': 60, 'INR': 2000, 'USD': 3};
      final total = totalInBase(
        byCurrency: by,
        baseCurrency: 'EUR',
        ratesForBaseTo: eurRates,
      );
      // 60*1 + 2000*0.0098 + 3*0.85 = 60 + 19.6 + 2.55 = 82.15
      expect(total, 82.15);
    });

    test('rounding is stable at 2 decimals', () {
      final by = <String, double>{'JPY': 1}; // 1 * 0.006 = 0.006 → 0.01
      final total = totalInBase(
        byCurrency: by,
        baseCurrency: 'EUR',
        ratesForBaseTo: eurRates,
      );
      expect(total, 0.01);
    });

    test('handles empty set', () {
      final t = totalInBase(
        byCurrency: const {},
        baseCurrency: 'EUR',
        ratesForBaseTo: eurRates,
      );
      expect(t, 0.0);
    });
  });
}
