import 'package:flutter/material.dart';

class InsightsCard extends StatelessWidget {
  const InsightsCard({
    super.key,
    required this.dailyBurn,
    required this.daysLeft,
    required this.baseCurrency,
    required this.byCategoryBase, // already converted to base
  });

  final double dailyBurn;
  final int daysLeft;
  final String baseCurrency;
  final Map<String, double> byCategoryBase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = byCategoryBase.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Insights', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                Text('Daily burn: ${dailyBurn.toStringAsFixed(2)} $baseCurrency'),
                Text('Days left: $daysLeft'),
              ],
            ),
            const SizedBox(height: 12),
            Text('By category', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            for (final e in cats)
              Row(
                children: [
                  Expanded(child: Text(e.key)),
                  Text('${e.value.toStringAsFixed(2)} $baseCurrency'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
