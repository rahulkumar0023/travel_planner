// models/monthly_txn.dart
// ▷ MonthlyTxn model start
enum MonthlyTxnKind { income, expense }

class MonthlyTxn {
  final String id;
  final String monthKey;        // "2025-08"
  final MonthlyTxnKind kind;    // income | expense
  final String currency;        // ISO 4217
  final double amount;
  final DateTime date;
  final String? categoryId;     // from CategoryStore (root)
  final String? subcategoryId;  // optional sub
  final String? note;

  MonthlyTxn({
    required this.id,
    required this.monthKey,
    required this.kind,
    required this.currency,
    required this.amount,
    required this.date,
    this.categoryId,
    this.subcategoryId,
    this.note,
  });

  factory MonthlyTxn.fromJson(Map<String, dynamic> j) => MonthlyTxn(
        id: j['id'],
        monthKey: j['monthKey'],
        kind: (j['kind'] == 'income') ? MonthlyTxnKind.income : MonthlyTxnKind.expense,
        currency: j['currency'],
        amount: (j['amount'] as num).toDouble(),
        date: DateTime.parse(j['date']),
        categoryId: j['categoryId'],
        subcategoryId: j['subcategoryId'],
        note: j['note'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'monthKey': monthKey,
        'kind': kind == MonthlyTxnKind.income ? 'income' : 'expense',
        'currency': currency,
        'amount': amount,
        'date': date.toIso8601String(),
        'categoryId': categoryId,
        'subcategoryId': subcategoryId,
        'note': note,
      };
}
// ◀ MonthlyTxn model end
