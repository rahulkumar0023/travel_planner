import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trip.dart';
import '../models/expense.dart';
import '../models/balance_row.dart';
import '../models/budget.dart'; // ← make sure you have this model

class ApiService {
  final String baseUrl;

  // Auth (set in Auth flow; attached to every request via _headers)
  String? _authToken;

  // NOTE: cannot be const because _authToken is mutable.
  ApiService({required this.baseUrl});

  /// Attach or clear bearer token (call this after successful sign-in).
  void setAuthToken(String? token) => _authToken = token;

  /// Standard headers for every call; adds Content-Type and Authorization when needed.
  Map<String, String> _headers({bool jsonBody = false}) {
    final h = <String, String>{};
    if (jsonBody) h['Content-Type'] = 'application/json';
    final t = _authToken;
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  // -----------------------------
  // Auth
  // -----------------------------
  Future<String> exchangeAuthToken({
    required String provider, // 'google' | 'apple'
    String? idToken,
    String? authCode,
  }) async {
    final payload = {
      'provider': provider,
      if (idToken != null) 'idToken': idToken,
      if (authCode != null) 'authorizationCode': authCode,
    };
    final res = await http.post(
      Uri.parse('$baseUrl/auth/exchange'),
      headers: _headers(jsonBody: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('Auth exchange failed: ${res.statusCode} ${res.body}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final token = (map['token'] ?? map['accessToken'] ?? map['jwt']) as String;
    setAuthToken(token);
    return token;
  }

  // -----------------------------
  // Trips
  // -----------------------------
  Future<List<Trip>> fetchTrips() async {
    final res = await http.get(Uri.parse('$baseUrl/trips'), headers: _headers());
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Trip.fromJson(e)).toList();
    }
    throw Exception('Failed to load trips (${res.statusCode})');
  }

  Future<Trip> createTrip(Trip t) async {
    final res = await http.post(
      Uri.parse('$baseUrl/trips'),
      headers: _headers(jsonBody: true),
      body: jsonEncode(t.toJson()),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to create trip (${res.statusCode})');
  }

  // -----------------------------
  // Expenses
  // -----------------------------
  Future<List<Expense>> fetchExpenses(String tripId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/expenses/$tripId'),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Expense.fromJson(e)).toList();
    }
    throw Exception('Failed to load expenses (${res.statusCode})');
  }

  Future<void> addExpense(Expense e) async {
    final res = await http.post(
      Uri.parse('$baseUrl/expenses'),
      headers: _headers(jsonBody: true),
      body: jsonEncode(e.toJson()),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to add expense (${res.statusCode})');
    }
  }

  // -----------------------------
  // Balances + Settle Up
  // -----------------------------
  Future<List<BalanceRow>> fetchGroupBalances(String tripId) async {
    // Prefer /balances/{tripId}; fallback to legacy /expenses/split/{tripId}
    var res = await http.get(
      Uri.parse('$baseUrl/balances/$tripId'),
      headers: _headers(),
    );
    if (res.statusCode == 404) {
      res = await http.get(
        Uri.parse('$baseUrl/expenses/split/$tripId'),
        headers: _headers(),
      );
    }
    if (res.statusCode != 200) {
      throw Exception('Balances fetch failed: ${res.statusCode} ${res.body}');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return list.map(BalanceRow.fromJson).toList();
  }

  Future<void> createSettlement({
    required String tripId,
    required String from,
    required String to,
    required double amount,
    required String currency,
    String? note,
    DateTime? date,
  }) async {
    final payload = {
      'tripId': tripId,
      'from': from,
      'to': to,
      'amount': amount,
      'currency': currency,
      if (note != null && note.isNotEmpty) 'note': note,
      if (date != null) 'date': date.toIso8601String(),
    };

    var res = await http.post(
      Uri.parse('$baseUrl/balances/settle'),
      headers: _headers(jsonBody: true),
      body: jsonEncode(payload),
    );

    // Fallback: legacy/alternate endpoint
    if (res.statusCode == 404) {
      res = await http.post(
        Uri.parse('$baseUrl/settlements'),
        headers: _headers(jsonBody: true),
        body: jsonEncode(payload),
      );
    }

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Settlement failed: ${res.statusCode} ${res.body}');
    }
  }

  // -----------------------------
  // Currency convert
  // -----------------------------
  /// Preferred (named params). Returns a concrete double; if conversion fails,
  /// it returns the original [amount].
  Future<double> convert({
    required double amount,
    required String from,
    required String to,
  }) async {
    if (amount == 0 || from.toUpperCase() == to.toUpperCase()) return amount;

    final uri = Uri.parse(
      '$baseUrl/currency/convert?amount=$amount&from=$from&to=$to',
    );
    final res = await http.get(uri, headers: _headers());
    if (res.statusCode != 200) return amount;

    final body = jsonDecode(res.body);

    // Accept many shapes:
    // { "converted": 12.34 } | { "result": 12.34 } | { "amount": 12.34 } | { "value": 12.34 }
    // or 12.34 | "12.34"
    if (body is Map<String, dynamic>) {
      for (final k in ['converted', 'result', 'amount', 'value']) {
        final v = body[k];
        if (v is num) return v.toDouble();
        if (v is String) {
          final d = double.tryParse(v);
          if (d != null) return d;
        }
      }
    } else if (body is num) {
      return body.toDouble();
    } else if (body is String) {
      final d = double.tryParse(body);
      if (d != null) return d;
    }
    return amount; // fallback
  }

  /// Backward-compatible wrapper for your previous positional signature.
  /// (You can delete calls to this once you switch to the named version above.)
  Future<double?> convertLegacy(double amount, String from, String to) async {
    final v = await convert(amount: amount, from: from, to: to);
    return v;
  }

  // -----------------------------
  // Budgets
  // -----------------------------
  Future<List<Budget>> fetchBudgets() async {
    final res = await http.get(
      Uri.parse('$baseUrl/budgets'),
      headers: _headers(),
    );
    if (res.statusCode == 404) return <Budget>[]; // backend not ready yet
    if (res.statusCode != 200) {
      throw Exception('Fetch budgets failed: ${res.statusCode} ${res.body}');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return list.map(Budget.fromJson).toList();
  }

  Future<Budget> createBudget({
    required BudgetKind kind,
    required String currency,
    required double amount,
    int? year,
    int? month,
    String? tripId,
    String? name,
  }) async {
    final payload = {
      'kind': kind == BudgetKind.monthly ? 'monthly' : 'trip',
      'currency': currency,
      'amount': amount,
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (tripId != null) 'tripId': tripId,
      if (name != null) 'name': name,
    };

    // Try common REST variants in order
    final endpoints = <String>[
      '$baseUrl/budgets',
      if (kind == BudgetKind.monthly) '$baseUrl/budgets/monthly' else '$baseUrl/budgets/trip',
      '$baseUrl/budget',
      if (kind == BudgetKind.monthly) '$baseUrl/budget/monthly' else '$baseUrl/budget/trip',
      '$baseUrl/api/budgets',
      if (kind == BudgetKind.monthly) '$baseUrl/api/budgets/monthly' else '$baseUrl/api/budgets/trip',
    ];

    Exception? lastError;

    for (final url in endpoints) {
      try {
        final res = await http.post(
          Uri.parse(url),
          headers: _headers(jsonBody: true),
          body: jsonEncode(payload),
        );

        // Success with body
        if (res.statusCode == 200 || res.statusCode == 201) {
          if (res.body.isNotEmpty) {
            final map = jsonDecode(res.body) as Map<String, dynamic>;
            return Budget.fromJson(map);
          }
          // Success without body → synthesize from payload + Location header if present
          final loc = res.headers['location'];
          final id = (loc != null && loc.trim().isNotEmpty)
              ? loc.split('/').last
              : DateTime.now().millisecondsSinceEpoch.toString();
          return Budget(
            id: id,
            kind: kind,
            currency: currency,
            amount: amount,
            year: year,
            month: month,
            tripId: tripId,
            name: name,
          );
        }

        // If 404, try the next candidate; otherwise capture error and continue
        if (res.statusCode != 404) {
          lastError = Exception('Create budget failed @ $url: '
              '${res.statusCode} ${res.body}');
        }
      } catch (e) {
        lastError = Exception('Create budget error @ $url: $e');
      }
    }

    // If none of the candidates worked, throw the most relevant error
    throw lastError ??
        Exception('Create budget failed: no budget endpoint available');
  }


  Future<void> linkTripBudget({
    required String tripBudgetId,
    required String monthlyBudgetId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/budgets/$tripBudgetId/link'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'monthlyBudgetId': monthlyBudgetId}),
    );
    if (res.statusCode == 404) {
      // Alternate legacy endpoint
      final res2 = await http.post(
        Uri.parse('$baseUrl/budget-links'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'tripBudgetId': tripBudgetId,
          'monthlyBudgetId': monthlyBudgetId,
        }),
      );
      if (res2.statusCode != 200 && res2.statusCode != 201) {
        throw Exception('Linking failed: ${res2.statusCode} ${res2.body}');
      }
      return;
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Linking failed: ${res.statusCode} ${res.body}');
    }
  }
}
