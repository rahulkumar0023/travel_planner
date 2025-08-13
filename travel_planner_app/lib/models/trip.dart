class Trip {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final double initialBudget;
  final String currency;

  Trip({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.initialBudget,
    required this.currency,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'],
        name: json['name'],
        startDate: DateTime.parse(json['startDate']),
        endDate: DateTime.parse(json['endDate']),
        initialBudget: json['initialBudget'],
        currency: json['currency'],
      );
}
