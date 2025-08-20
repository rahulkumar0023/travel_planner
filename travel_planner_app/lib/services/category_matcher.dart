import '../models/monthly_category.dart';

/// Returns (catId, subId) if a human string matches any subcategory name.
({String catId, String subId})? matchByName(
  String expenseCategory,
  List<MonthlyCategory> envelopes,
) {
  final q = expenseCategory.trim().toLowerCase();
  for (final c in envelopes) {
    for (final s in c.subs) {
      if (s.name.trim().toLowerCase() == q) {
        return (catId: c.id, subId: s.id);
      }
    }
  }
  // fallback: match main category
  for (final c in envelopes) {
    if (c.name.trim().toLowerCase() == q && c.subs.isNotEmpty) {
      return (catId: c.id, subId: c.subs.first.id);
    }
  }
  return null;
}
