import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/expense.dart';
import '../models/group_balance.dart';
import '../models/trip.dart';

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
  static Future<List<GroupBalance>> fetchGroupBalances(String tripId) async {
    final res = await http.get(Uri.parse('$baseUrl/balances/$tripId'));
    if (res.statusCode == 404) return <GroupBalance>[];
    if (res.statusCode != 200) {
      throw Exception('Split fetch failed: ${res.statusCode} ${res.body}');
    }
    final data = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return data.map(GroupBalance.fromJson).toList();
  }

  // ----- currency -----
  static Future<double> convert({
    required double amount,
    required String from,
    required String to,
  }) async {
    final uri =
        Uri.parse('$baseUrl/currency/convert?amount=$amount&from=$from&to=$to');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Convert failed: ${res.statusCode}');
    }
    final obj = jsonDecode(res.body) as Map<String, dynamic>;
    return (obj['amount'] as num).toDouble();
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

