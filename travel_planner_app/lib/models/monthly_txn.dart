// ===== monthly_txn.dart — START =====
// Description: Hive model for Monthly Transactions (salary & expenses) tracked per month.
// TypeId: pick a free one; example: 42.

import 'package:hive/hive.dart';

part 'monthly_txn.g.dart';

@HiveType(typeId: 42)
class MonthlyTxn extends HiveObject {
  @HiveField(0)
  String id; // uuid

  @HiveField(1)
  String monthKey; // 'YYYY-MM'

  @HiveField(2)
  String categoryId; // link to MonthlyCategory (can be sub-category)

  @HiveField(3)
  double amount;

  @HiveField(4)
  String currency; // store entered currency

  @HiveField(5)
  String note;

  @HiveField(6)
  DateTime date;

  @HiveField(7)
  String type; // 'income' | 'expense' (redundant but handy for queries)

  MonthlyTxn({
    required this.id,
    required this.monthKey,
    required this.categoryId,
    required this.amount,
    required this.currency,
    required this.note,
    required this.date,
    required this.type,
  });
}
// ===== monthly_txn.dart — END =====
