import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trip.dart';
import '../models/expense.dart';
import '../models/balance_row.dart';

class ApiService {
  final String baseUrl;
  const ApiService({required this.baseUrl});

  // --- Trips ---
  Future<List<Trip>> fetchTrips() async {
    final res = await http.get(Uri.parse('$baseUrl/trips'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Trip.fromJson(e)).toList();
    }
    throw Exception('Failed to load trips (${res.statusCode})');
  }

  Future<Trip> createTrip(Trip t) async {
    final res = await http.post(
      Uri.parse('$baseUrl/trips'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(t.toJson()),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to create trip (${res.statusCode})');
  }

  // --- Expenses (optional now; dashboard shows local for speed) ---
  Future<List<Expense>> fetchExpenses(String tripId) async {
    final res = await http.get(Uri.parse('$baseUrl/expenses/$tripId'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Expense.fromJson(e)).toList();
    }
    throw Exception('Failed to load expenses (${res.statusCode})');
  }

  Future<double?> convert(double amount, String from, String to) async {
    final uri =
        Uri.parse('$baseUrl/currency/convert?amount=$amount&from=$from&to=$to');
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body);

    // Accept any of these payloads:
    // { "amount": 12.34 }  or  { "value": 12.34 }  or  12.34  or  "12.34"
    if (body is Map<String, dynamic>) {
      final v = body['amount'] ?? body['value'];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
    }
    if (body is num) return body.toDouble();
    if (body is String) return double.tryParse(body);

    return null;
  }

  Future<void> addExpense(Expense e) async {
    final res = await http.post(
      Uri.parse('$baseUrl/expenses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(e.toJson()),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to add expense (${res.statusCode})');
    }
  }

  Future<List<BalanceRow>> fetchGroupBalances(String tripId) async {
    // Prefer /balances/{tripId}; fallback to legacy /expenses/split/{tripId}
    var res = await http.get(Uri.parse('$baseUrl/balances/$tripId'));
    if (res.statusCode == 404) {
      res = await http.get(Uri.parse('$baseUrl/expenses/split/$tripId'));
    }
    if (res.statusCode != 200) {
      throw Exception('Balances fetch failed: ${res.statusCode} ${res.body}');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return list.map(BalanceRow.fromJson).toList();
  }
}
