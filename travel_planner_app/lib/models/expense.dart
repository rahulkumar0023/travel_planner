import 'package:hive/hive.dart';
part 'expense.g.dart';

@HiveType(typeId: 0)
class Expense extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String tripId;
  @HiveField(2)
  String title;
  @HiveField(3)
  double amount;
  @HiveField(4)
  String category;
  @HiveField(5)
  DateTime date;
  @HiveField(6)
  String paidBy;
  @HiveField(7)
  List<String> sharedWith;
  @HiveField(8)
  String currency; // <-- add

  Expense({
    required this.id,
    required this.tripId,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.paidBy,
    required this.sharedWith,
    required this.currency, // <-- add
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: (json['id'] as String?) ?? '',
    tripId: (json['tripId'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    category: (json['category'] as String?) ?? '',
    date: DateTime.parse((json['date'] as String?) ?? DateTime.now().toIso8601String()),
    paidBy: (json['paidBy'] as String?) ?? '',
    sharedWith: (json['sharedWith'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
    currency: (json['currency'] as String?) ?? '',
  );


// toJson
  Map<String, dynamic> toJson() => {
    'id': id,
    'tripId': tripId,
    'title': title,
    'amount': amount,
    'category': category,
    'date': date.toIso8601String(),
    'paidBy': paidBy,
    'sharedWith': sharedWith,
    'currency': currency, // <-- add
  };
}
