import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/expense.dart';
import '../models/trip.dart';
import '../models/budget.dart';

// ⚠️ set this to your Render URL
class ApiService {
  static const String baseUrl = 'https://travel-planner-api-uo05.onrender.com';

  // ----- trips -----
  static Future<List<Trip>> fetchTrips() async {
    final res = await http.get(Uri.parse('$baseUrl/trips'));
    if (res.statusCode != 200) {
      throw Exception('Trips fetch failed: ${res.statusCode}');
    }
    final data = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return data.map(Trip.fromJson).toList();
  }

  static Future<Trip> addTrip(Trip t) async {
    final res = await http.post(
      Uri.parse('$baseUrl/trips'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(t.toJson(withId: false)),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Trip create failed: ${res.statusCode} ${res.body}');
    }
    return Trip.fromJson(jsonDecode(res.body));
  }

  // ----- expenses -----
  static Future<List<Expense>> fetchExpenses(String tripId) async {
    final res = await http.get(Uri.parse('$baseUrl/expenses/$tripId'));
    if (res.statusCode != 200) {
      throw Exception('Expenses fetch failed: ${res.statusCode}');
    }
    final data = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return data.map(Expense.fromJson).toList();
  }

  static Future<void> addExpense(Expense e) async {
    final res = await http.post(
      Uri.parse('$baseUrl/expenses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(e.toJson()),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Expense create failed: ${res.statusCode} ${res.body}');
    }
  }

  // ----- balances -----
  static Future<List<Map<String, dynamic>>> fetchGroupBalances(String tripId) async {
    final url = Uri.parse('$baseUrl/balances/$tripId');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Failed to load balances: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching balances: $e');
      return [];
    }
  }

  // ----- budgets -----
  static Future<MonthlyBudgetSummary> fetchMonthlySummary(
      DateTime month) async {
    // TODO: call /budgets/summary?month=YYYY-MM
    // For now, return mock to see UI immediately
    return MonthlyBudgetSummary(
      month: DateTime(month.year, month.month),
      currency: 'EUR',
      initialBalance: 5537,
      totalBudgeted: 5537,
      totalSpent: 5050.46,
      remaining: 5537 - 5050.46,
    );
  }

  static Future<List<Budget>> fetchMonthlyBudgets(DateTime month) async {
    // TODO: call /budgets?month=YYYY-MM (or your chosen endpoint)
    // Mock data to visualize
    return [
      Budget(
          id: 'b1',
          name: 'Recurring',
          currency: 'EUR',
          planned: 917.84,
          spent: 867.27,
          colorIndex: 0),
      Budget(
          id: 'b2',
          name: 'Shared household and living',
          currency: 'EUR',
          planned: 500,
          spent: 500,
          colorIndex: 1),
      Budget(
          id: 'b3',
          name: 'Discretionary and Flex',
          currency: 'EUR',
          planned: 458,
          spent: 22.03,
          colorIndex: 2),
      Budget(
          id: 'b4',
          name: 'Emergency fund',
          currency: 'EUR',
          planned: 3026.8,
          spent: 3026.8,
          colorIndex: 3),
      Budget(
          id: 'b5',
          name: 'Company loan repayment',
          currency: 'EUR',
          planned: 100,
          spent: 100,
          colorIndex: 4),
    ];
  }

  // ----- currency -----
  static Future<double> convert(double amount, String fromCurrency, String toCurrency) async {
    if (amount == 0 || fromCurrency == toCurrency) {
      return amount;
    }

    final url = Uri.parse('$baseUrl/currency/convert?amount=$amount&from=$fromCurrency&to=$toCurrency');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['convertedAmount'] as num).toDouble();
      } else {
        print('Currency conversion failed: ${response.statusCode}');
        return amount;
      }
    } catch (e) {
      print('Error converting currency: $e');
      return amount;
    }
  }

  // ----- itinerary -----
  static Future<List<DayPlan>> generateItinerary({
    required String destination,
    required int days,
    required String budgetLevel,
    required List<String> interests,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/itinerary'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'destination': destination,
        'days': days,
        'budgetLevel': budgetLevel,
        'interests': interests,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Itinerary failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['plan'] as List).cast<Map<String, dynamic>>();
    return list.map((e) => DayPlan.fromJson(e)).toList();
  }
}

// support types for itinerary
class DayPlan {
  final int day;
  final List<String> items;
  DayPlan({required this.day, required this.items});

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        day: (j['day'] as num).toInt(),
        items: (j['items'] as List).map((e) => e.toString()).toList(),
      );
}

