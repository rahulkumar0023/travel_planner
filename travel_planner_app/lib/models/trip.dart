class Trip {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final double initialBudget;
  final String currency;
  final List<String> participants;
  final List<String> spendCurrencies;
  final String? notes;

  Trip({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.currency,
    required this.initialBudget,
    required this.participants,
    this.spendCurrencies = const [], // <-- add default
    this.notes,
  });

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        name: j['name'] as String,
        startDate: DateTime.parse(j['startDate'] as String),
        endDate: DateTime.parse(j['endDate'] as String),
        currency: (j['currency'] as String).toUpperCase(),
        initialBudget: (j['initialBudget'] as num).toDouble(),
        participants: (j['participants'] as List).cast<String>(),
        spendCurrencies: (j['spendCurrencies'] as List? ?? const [])
            .cast<String>()
            .map((e) => e.toUpperCase())
            .toList(),
        notes: () {
          final raw = j['notes'] as String?;
          if (raw == null) return null;
          final trimmed = raw.trim();
          return trimmed.isEmpty ? null : trimmed;
        }(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': _yyyyMmDd(startDate),
        'endDate': _yyyyMmDd(endDate),
        'currency': currency,
        'initialBudget': initialBudget,
        'participants': participants,
        'spendCurrencies': spendCurrencies,
        'notes': notes,
      };

  Trip copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    double? initialBudget,
    String? currency,
    List<String>? participants,
    List<String>? spendCurrencies,
    Object? notes = _sentinel,
  }) {
    return Trip(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      currency: currency ?? this.currency,
      initialBudget: initialBudget ?? this.initialBudget,
      participants: participants ?? this.participants,
      spendCurrencies: spendCurrencies ?? this.spendCurrencies,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
    );
  }

  static const Object _sentinel = Object();

  String _yyyyMmDd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
