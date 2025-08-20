import 'package:hive/hive.dart';
import '../models/expense.dart';
import '../models/envelope.dart';
import '../models/budget.dart';
import '../services/api_service.dart';
import '../services/envelope_store.dart';
import '../services/envelope_links_store.dart';
import '../services/prefs_service.dart';

class MonthlyBudgetSummary {
  final String currency;          // monthly currency (home)
  final double totalIncomePlanned;
  final double totalExpensePlanned;
  final double totalSpent;
  MonthlyBudgetSummary({
    required this.currency,
    required this.totalIncomePlanned,
    required this.totalExpensePlanned,
    required this.totalSpent,
  });

  double get remaining => (totalExpensePlanned - totalSpent);
  double get pctSpent => (totalIncomePlanned <= 0)
      ? (totalExpensePlanned <= 0 ? 0 : (totalSpent / totalExpensePlanned))
      : (totalSpent / totalIncomePlanned);
}

class MonthlyService {
  final ApiService api;
  MonthlyService(this.api);

  // Compute envelopes + summary for a month
  // month is any date within that month (year/month used)
  Future<({
    MonthlyBudgetSummary summary,
    List<EnvelopeSpend> envelopes,
  })> load(DateTime month) async {
    final monthlyCurrency = await PrefsService.getHomeCurrency();

    // 1) Load envelope definitions (planned)
    final defs = await EnvelopeStore.load(month);

    // 2) Gather spent from local expenses by month (Hive)
    final box = Hive.box<Expense>('expensesBox');
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final monthExpenses = box.values.where((e) => e.date.isAfter(start.subtract(const Duration(milliseconds: 1))) && e.date.isBefore(end)).toList();

    // Sum spent per category (case-insensitive name match)
    final spendByName = <String, double>{}; // in monthlyCurrency
    for (final e in monthExpenses) {
      final from = (e.currency.isEmpty) ? monthlyCurrency : e.currency.toUpperCase();
      final to = monthlyCurrency.toUpperCase();
      final converted = (from == to)
          ? e.amount
          : await api.convert(amount: e.amount, from: from, to: to);
      final key = e.category.trim().toLowerCase();
      spendByName[key] = (spendByName[key] ?? 0) + converted;
    }

    // 3) Pull Trip budgets that are *linked to this month* via your existing Monthly budgets
    // We inspect your /budgets to find monthly budgets for this month,
    // then include Trip budgets whose linkedMonthlyBudgetId matches.
    final allBudgets = await api.fetchBudgetsOrCache();
    final monthlyBudgets = allBudgets.where((b) =>
      b.kind == BudgetKind.monthly && b.year == month.year && b.month == month.month
    ).toList();
    final monthlyIds = monthlyBudgets.map((b) => b.id).toSet();
    final tripBudgetsForThisMonth = allBudgets.where((b) =>
      b.kind == BudgetKind.trip && b.linkedMonthlyBudgetId != null && monthlyIds.contains(b.linkedMonthlyBudgetId!)
    ).toList();

    // 4) Use EnvelopeLinks to attribute Trip budget *planned* into an envelope
    final links = await EnvelopeLinksStore.load(month); // { tripBudgetId: envelopeId }
    final plannedBumps = <String, double>{}; // envelopeId -> amount to add
    for (final tb in tripBudgetsForThisMonth) {
      final envelopeId = links[tb.id];
      if (envelopeId == null) continue;
      // convert Trip budget amount to monthly currency
      final to = monthlyCurrency.toUpperCase();
      final from = tb.currency.toUpperCase();
      final bump = (from == to)
          ? tb.amount
          : await api.convert(amount: tb.amount, from: from, to: to);
      plannedBumps[envelopeId] = (plannedBumps[envelopeId] ?? 0) + bump;
    }

    // 5) Build EnvelopeSpend list (planned may include linked trip budgets)
    final envSpends = <EnvelopeSpend>[];
    for (final d in defs) {
      // normalize planned into monthlyCurrency (definitions should already be in home)
      final plannedInMonthly = (d.currency.toUpperCase() == monthlyCurrency.toUpperCase())
          ? d.planned
          : await api.convert(amount: d.planned, from: d.currency, to: monthlyCurrency);

      final bump = plannedBumps[d.id] ?? 0.0;
      final spent = spendByName[d.name.trim().toLowerCase()] ?? 0.0;
      envSpends.add(EnvelopeSpend(
        def: d.copyWith(planned: plannedInMonthly + bump, currency: monthlyCurrency),
        spent: spent,
      ));
    }

    // 6) Totals
    final totalIncomePlanned = envSpends
        .where((e) => e.def.type == EnvelopeType.income)
        .fold<double>(0.0, (p, e) => p + e.def.planned);
    final totalExpensePlanned = envSpends
        .where((e) => e.def.type == EnvelopeType.expense)
        .fold<double>(0.0, (p, e) => p + e.def.planned);
    final totalSpent = envSpends
        .where((e) => e.def.type == EnvelopeType.expense) // we only count expense spend
        .fold<double>(0.0, (p, e) => p + e.spent);

    final summary = MonthlyBudgetSummary(
      currency: monthlyCurrency,
      totalIncomePlanned: totalIncomePlanned,
      totalExpensePlanned: totalExpensePlanned,
      totalSpent: totalSpent,
    );

    return (summary: summary, envelopes: envSpends);
  }
}

