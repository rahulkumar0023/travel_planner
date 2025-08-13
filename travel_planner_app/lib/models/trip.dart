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

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'],
      name: json['name'],
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      initialBudget: json['initialBudget'].toDouble(),
      currency: json['currency'],
      participants: List<String>.from(json['participants']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'initialBudget': initialBudget,
      'currency': currency,
      'participants': participants,
    };
  }
}
