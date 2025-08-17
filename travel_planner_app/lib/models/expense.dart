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

// fromJson
  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'] as String,
    tripId: j['tripId'] as String,
    title: j['title'] as String,
    amount: (j['amount'] as num).toDouble(),
    category: j['category'] as String,
    date: DateTime.parse(j['date'] as String),
    paidBy: j['paidBy'] as String,
    sharedWith: (j['sharedWith'] as List).cast<String>(),
    currency: (j['currency'] as String).toUpperCase(), // <-- add
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
