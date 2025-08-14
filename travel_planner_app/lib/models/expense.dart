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

  Expense({
    required this.id,
    required this.tripId,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.paidBy,
    required this.sharedWith,
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        tripId: json['tripId'],
        title: json['title'],
        amount: (json['amount'] ?? 0).toDouble(),
        category: json['category'],
        date: DateTime.parse(json['date']),
        paidBy: json['paidBy'] ?? '',
        sharedWith: (json['sharedWith'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tripId': tripId,
        'title': title,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'paidBy': paidBy,
        'sharedWith': sharedWith,
      };
}
