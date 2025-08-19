import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_planner_app/widgets/insights_card.dart';

void main() {
  testWidgets('InsightsCard shows burn, days, and categories', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InsightsCard(
            dailyBurn: 12.345,
            daysLeft: 7,
            baseCurrency: 'EUR',
            byCategoryBase: {'Food': 50.0, 'Transport': 20.0},
          ),
        ),
      ),
    );

    expect(find.textContaining('Daily burn:'), findsOneWidget);
    expect(find.text('Days left: 7'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('50.00 EUR'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('20.00 EUR'), findsOneWidget);
  });
}
