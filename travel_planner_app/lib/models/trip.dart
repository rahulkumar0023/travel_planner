class Trip {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final double initialBudget;
  final String currency;
  final List<String> participants;

  Trip({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.initialBudget,
    required this.currency,
    required this.participants,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'],
        name: json['name'],
        startDate: DateTime.parse(json['startDate']),
        endDate: DateTime.parse(json['endDate']),
        initialBudget: (json['initialBudget'] ?? 0).toDouble(),
        currency: json['currency'],
        participants:
            (json['participants'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'initialBudget': initialBudget,
        'currency': currency,
        'participants': participants,
      };
}
