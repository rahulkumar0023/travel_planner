import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/expense.dart';
import '../models/trip.dart';
import '../models/group_balance.dart';

class ApiService {
  static const String baseUrl =
      'https://travel-planner-api-uo05.onrender.com'; // 👈 Replace this

  // Fetch all expenses for a trip
  static Future<List<Expense>> fetchExpenses(String tripId) async {
    final url = Uri.parse('$baseUrl/expenses/$tripId');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => Expense.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load expenses');
    }
  }

  // Add a new expense
  static Future<void> addExpense(Expense expense) async {
    final url = Uri.parse('$baseUrl/expenses');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(expense.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to add expense');
    }
  }

  // Fetch all trips
  static Future<List<Trip>> fetchTrips() async {
    final url = Uri.parse('$baseUrl/trips');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((t) => Trip.fromJson(t)).toList();
    } else {
      throw Exception('Failed to load trips');
    }
  }

  // Add a new trip
  static Future<void> addTrip(Trip trip) async {
    final url = Uri.parse('$baseUrl/trips');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(trip.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to add trip');
    }
  }

  static Future<List<GroupBalance>> fetchGroupBalances(String tripId) async {
    final url =
        '$baseUrl/balances/$tripId'; // 👈 make sure this path matches your backend
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 404) {
      return <GroupBalance>[]; // treat "trip not found" as empty
    }

    if (res.statusCode != 200) {
      throw Exception('Split fetch failed: ${res.statusCode} ${res.body}');
    }
    final data = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return data.map(GroupBalance.fromJson).toList();
  }

  // Currency convert (works with your updated backend)
  static Future<double> convert({
    required double amount,
    required String from,
    required String to,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/currency/convert?amount=$amount&from=$from&to=$to',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Convert failed: ${res.statusCode} ${res.body}');
    }
    final obj = jsonDecode(res.body) as Map<String, dynamic>;
    return (obj['amount'] as num).toDouble();
  }
}
