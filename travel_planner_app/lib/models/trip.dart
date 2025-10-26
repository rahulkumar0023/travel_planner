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
        id: (j['id'] ?? j['tripId'] ?? j['uuid']).toString(),
        name: (j['name'] ?? '').toString(),
        startDate: _parseDate(j['startDate']) ?? DateTime.now(),
        endDate: _parseDate(j['endDate']) ?? DateTime.now(),
        currency: (j['currency']?.toString() ?? 'EUR').toUpperCase(),
        initialBudget: _numToDouble(j['initialBudget']) ?? 0.0,
        participants: _parseParticipants(j['participants']),
        spendCurrencies: (j['spendCurrencies'] as List? ?? const [])
            .map((e) => e.toString().toUpperCase())
            .toList(),
        notes: () {
          final raw = j['notes']?.toString();
          if (raw == null) return null;
          final trimmed = raw.trim();
          return trimmed.isEmpty ? null : trimmed;
        }(),
      );

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) {
      try { return DateTime.parse(v); } catch (_) {}
    }
    return null;
  }

  static double? _numToDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static List<String> _parseParticipants(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      return v.map((e) {
        if (e is String) return e;
        if (e is Map) {
          final m = e.cast<dynamic, dynamic>();
          return (m['email'] ?? m['userId'] ?? m['id'] ?? '').toString();
        }
        return e.toString();
      }).where((s) => s.isNotEmpty).toList();
    }
    return const <String>[];
  }

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
