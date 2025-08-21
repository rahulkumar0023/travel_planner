// ===== monthly_txn.dart — START =====
// Description: Model for Monthly Transactions (salary & expenses).

enum MonthlyTxnKind { income, expense }

class MonthlyTxn {
  final String id;
  final MonthlyTxnKind kind;
  final String currency;
  final double amount;
  final String? categoryId;
  final String? subCategoryId;
  final String note;
  final DateTime date;

  MonthlyTxn({
    required this.id,
    required this.kind,
    required this.currency,
    required this.amount,
    this.categoryId,
    this.subCategoryId,
    this.note = '',
    required this.date,
  });

  factory MonthlyTxn.fromJson(Map<String, dynamic> json) => MonthlyTxn(
        id: json['id'] as String,
        kind: MonthlyTxnKind.values.firstWhere(
            (k) => k.name == (json['kind'] as String? ?? 'expense'),
            orElse: () => MonthlyTxnKind.expense),
        currency: json['currency'] as String? ?? '',
        amount: (json['amount'] as num).toDouble(),
        categoryId: json['categoryId'] as String?,
        subCategoryId: json['subCategoryId'] as String?,
        note: json['note'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'currency': currency,
        'amount': amount,
        if (categoryId != null) 'categoryId': categoryId,
        if (subCategoryId != null) 'subCategoryId': subCategoryId,
        'note': note,
        'date': date.toIso8601String(),
      };
}
// ===== monthly_txn.dart — END =====
