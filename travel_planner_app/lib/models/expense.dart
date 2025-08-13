class Expense {
  final String id;
  final String tripId;
  final String title;
  final double amount;
  final String category;
  final DateTime date;

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
