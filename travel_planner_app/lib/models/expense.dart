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

  Expense({
    required this.id,
    required this.tripId,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        tripId: json['tripId'],
        title: json['title'],
        amount: json['amount'],
        category: json['category'],
        date: DateTime.parse(json['date']),
      );
}
