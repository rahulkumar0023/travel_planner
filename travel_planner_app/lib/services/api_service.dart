import 'dart:convert';

import 'package:flutter/foundation.dart'; // ← make sure you have this model
import 'package:http/http.dart' as http;

import '../models/balance_row.dart';
import '../models/budget.dart';
import '../models/trip.dart';
import 'local_budget_store.dart';
import 'dart:async';
import 'local_trip_store.dart';
// ===== Expenses imports start =====
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_expense_store.dart';
import 'pending_ops_queue.dart';
import '../models/expense.dart';
import 'budgets_sync.dart';
import 'package:hive/hive.dart';
// ===== Expenses imports end =====

class _FxCache {
  _FxCache(this.rate, this.ts);

  final double rate;
  final DateTime ts;
}

class ApiService {
  final String baseUrl;

  // Auth (set in Auth flow; attached to every request via _headers)
  String? _authToken;
  bool lastBudgetsFromCache = false;
  bool lastTripsFromCache = false;
// ===== Expenses lastFromCache flag start =====
  bool lastExpensesFromCache = false;
// ===== Expenses lastFromCache flag end =====
  final Box<Expense> _expensesBox = Hive.box<Expense>('expensesBox');

// --- FX cache (1h TTL) ---
  final Map<String, _FxCache> _fx = {}; // key: 'FROM_TO'

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

  Future<List<Trip>> fetchTripsOrCache({Duration timeout = const Duration(seconds: 5)}) async {
    lastTripsFromCache = false;
    try {
      final res = await fetchTrips().timeout(timeout);
      // ignore: unawaited_futures
      LocalTripStore.save(res);
      return res;
    } catch (_) {
      lastTripsFromCache = true;
      return LocalTripStore.load();
    }
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
    // include body for easier debugging
    throw Exception('Failed to create trip (${res.statusCode}) ${res.body}');
  }

  Future<Trip> updateTrip(Trip t) async {
    final res = await http.put(
      Uri.parse('$baseUrl/trips/${t.id}'),
      headers: _headers(jsonBody: true),
      body: jsonEncode(t.toJson()),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update trip (${res.statusCode}) ${res.body}');
    }
    return Trip.fromJson(jsonDecode(res.body));
  }

  Future<void> deleteTrip(String id) async {
    final res = await http.delete(Uri.parse('$baseUrl/trips/$id'), headers: _headers());
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('Failed to delete trip (${res.statusCode}) ${res.body}');
    }
  }

  // ----------------------------- // Expenses fetch list start
  // fetchExpensesOrCache method start
  Future<List<Expense>> fetchExpensesOrCache(String tripId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/expenses?tripId=$tripId'), headers: _headers());
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        final expenses = list.map((m) => Expense.fromJson(m)).toList();
        await LocalExpenseStore.saveExpensesForTrip(tripId, expenses);
        lastExpensesFromCache = false;
        return expenses;
      }
      final cached = await LocalExpenseStore.loadExpensesForTrip(tripId);
      lastExpensesFromCache = true;
      return cached;
    } catch (_) {
      final cached = await LocalExpenseStore.loadExpensesForTrip(tripId);
      lastExpensesFromCache = true;
      return cached;
    }
  }
  // fetchExpensesOrCache method end
  // ----------------------------- // Expenses fetch list end

  // create Expense start
  Future<Expense> createExpense(Expense draft) async {
    final local = Expense(
      id: draft.id,
      tripId: draft.tripId,
      title: draft.title,
      amount: draft.amount,
      category: draft.category,
      date: draft.date,
      paidBy: draft.paidBy,
      sharedWith: draft.sharedWith,
      currency: draft.currency,
    );
    await _expensesBox.add(local);
    BudgetsSync.bump();

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/expenses'),
        headers: _headers(jsonBody: true),
        body: jsonEncode(draft.toJson()),
      );
      if (res.statusCode == 201) {
        final created = Expense.fromJson(jsonDecode(res.body));
        await _replaceLocalExpense(local, created);
        if (created.tripId.isNotEmpty) {
          final fresh = await fetchExpensesOrCache(created.tripId);
          await _reSeedHiveForTrip(created.tripId, fresh);
        }
        BudgetsSync.bump();
        return created;
      }
      await PendingOpsQueue.enqueue({'op': 'create', 'payload': draft.toJson()});
      return local;
    } catch (_) {
      await PendingOpsQueue.enqueue({'op': 'create', 'payload': draft.toJson()});
      return local;
    }
  }
  // create Expense end

  // update Expense start
  Future<Expense> updateExpense(Expense updated) async {
    await _updateLocalExpense(updated);
    BudgetsSync.bump();

    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/expenses/${updated.id}'),
        headers: _headers(jsonBody: true),
        body: jsonEncode(updated.toJson()),
      );
      if (res.statusCode == 200) {
        final server = Expense.fromJson(jsonDecode(res.body));
        await _updateLocalExpense(server);
        if (server.tripId.isNotEmpty) {
          final fresh = await fetchExpensesOrCache(server.tripId);
          await _reSeedHiveForTrip(server.tripId, fresh);
        }
        BudgetsSync.bump();
        return server;
      }
      await PendingOpsQueue.enqueue({'op': 'update', 'payload': updated.toJson()});
      return updated;
    } catch (_) {
      await PendingOpsQueue.enqueue({'op': 'update', 'payload': updated.toJson()});
      return updated;
    }
  }
  // update Expense end

  // delete Expense start
  Future<void> deleteExpense(Expense e) async {
    await _deleteLocalExpense(e);
    BudgetsSync.bump();

    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/expenses/${e.id}'),
        headers: _headers(),
      );
      if (res.statusCode == 200 || res.statusCode == 204) {
        if (e.tripId.isNotEmpty) {
          final fresh = await fetchExpensesOrCache(e.tripId);
          await _reSeedHiveForTrip(e.tripId, fresh);
        }
        BudgetsSync.bump();
        return;
      }
      await PendingOpsQueue.enqueue({'op': 'delete', 'payload': e.toJson()});
    } catch (_) {
      await PendingOpsQueue.enqueue({'op': 'delete', 'payload': e.toJson()});
    }
  }
  // delete Expense end

  // expenses syncPending start
  Future<void> syncPendingExpensesIfOnline() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    final items = await PendingOpsQueue.drain();
    for (final item in items) {
      final op = item['op'] as String;
      final payload = Map<String, dynamic>.from(item['payload'] as Map);
      try {
        if (op == 'create') {
          await http.post(
            Uri.parse('$baseUrl/expenses'),
            headers: _headers(jsonBody: true),
            body: jsonEncode(payload),
          );
        } else if (op == 'update') {
          final id = payload['id'];
          await http.patch(
            Uri.parse('$baseUrl/expenses/$id'),
            headers: _headers(jsonBody: true),
            body: jsonEncode(payload),
          );
        } else if (op == 'delete') {
          final id = payload['id'];
          await http.delete(
            Uri.parse('$baseUrl/expenses/$id'),
            headers: _headers(),
          );
        }
      } catch (_) {
        await PendingOpsQueue.enqueue(item);
      }
    }
    BudgetsSync.bump();
  }
  // expenses syncPending end

  // ===== Expenses helpers start =====
  // _replaceLocalExpense start
  Future<void> _replaceLocalExpense(Expense optimistic, Expense server) async {
    final idx = _expensesBox.values.toList().indexWhere((e) {
      return e.id == optimistic.id ||
          (e.title == optimistic.title && e.amount == optimistic.amount && e.date == optimistic.date);
    });
    if (idx >= 0) {
      final key = _expensesBox.keyAt(idx);
      await _expensesBox.put(key, server);
    } else {
      await _expensesBox.add(server);
    }
  }
  // _replaceLocalExpense end

  // _updateLocalExpense start
  Future<void> _updateLocalExpense(Expense e) async {
    final idx = _expensesBox.values.toList().indexWhere((x) => x.id == e.id);
    if (idx >= 0) {
      final key = _expensesBox.keyAt(idx);
      await _expensesBox.put(key, e);
    }
  }
  // _updateLocalExpense end

  // _deleteLocalExpense start
  Future<void> _deleteLocalExpense(Expense e) async {
    final idx = _expensesBox.values.toList().indexWhere((x) => x.id == e.id);
    if (idx >= 0) {
      final key = _expensesBox.keyAt(idx);
      await _expensesBox.delete(key);
    }
  }
  // _deleteLocalExpense end

  // _reSeedHiveForTrip start
  Future<void> _reSeedHiveForTrip(String tripId, List<Expense> fresh) async {
    final keysToDelete = <dynamic>[];
    for (var i = 0; i < _expensesBox.length; i++) {
      final v = _expensesBox.getAt(i) as Expense;
      if (v.tripId == tripId) {
        keysToDelete.add(_expensesBox.keyAt(i));
      }
    }
    await _expensesBox.deleteAll(keysToDelete);
    for (final e in fresh) {
      await _expensesBox.add(e);
    }
  }
  // _reSeedHiveForTrip end
  // ===== Expenses helpers end =====

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
// REPLACE your convert(...) with this version
  Future<double> convert({
    required double amount,
    required String from,
    required String to,
  }) async {
    // REPLACE convert(...) BODY with:
    {
      final f = from.toUpperCase();
      final t = to.toUpperCase();
      if (amount == 0 || f == t) return amount;

      // 1h TTL
      final key = '${f}_${t}';
      final now = DateTime.now();
      final ttl = const Duration(hours: 1);

      // Use cached rate if fresh
      final hit = _fx[key];
      if (hit != null && now.difference(hit.ts) < ttl) {
        return amount * hit.rate;
      }

      // Fetch rate with amount=1 and cache it
      final one = await _convertRaw(amount: 1.0, from: f, to: t);
      if (one > 0) {
        _fx[key] = _FxCache(one, now);
        return amount * one;
      }

      // Fallback to direct conversion of the full amount
      return await _convertRaw(amount: amount, from: f, to: t);
    }
  }

  /// Backward-compatible wrapper for your previous positional signature.
  /// (You can delete calls to this once you switch to the named version above.)
  Future<double?> convertLegacy(double amount, String from, String to) async {
    final v = await convert(amount: amount, from: from, to: to);
    return v;
  }

  Future<double> _convertRaw({
    required double amount,
    required String from,
    required String to,
  }) async {
    // This is essentially your current convert() logic without caching.
    if (amount == 0 || from.toUpperCase() == to.toUpperCase()) return amount;
    final uri = Uri.parse('$baseUrl/currency/convert').replace(
      queryParameters: {
        'from': from.toUpperCase(),
        'to': to.toUpperCase(),
        'amount': amount.toString(),
      },
    );
    final res = await http.get(uri, headers: _headers());
    if (res.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('convert(raw) HTTP ${res.statusCode}: ${res.body}');
      }
      return amount;
    }
    try {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        final v = body['amount'] ??
            body['converted'] ??
            body['result'] ??
            body['value'];
        if (v is num) return v.toDouble();
        if (v is String) {
          final d = double.tryParse(v);
          if (d != null) return d;
        }
      } else if (body is num) {
        return body.toDouble();
      } else if (body is String) {
        final d = double.tryParse(body);
        if (d != null) return d;
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('convert(raw) parse error: $e — body: ${res.body}');
    }
    return amount;
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

  /// Same as fetchBudgets but with a timeout and cache fallback.
  Future<List<Budget>> fetchBudgetsOrCache({Duration timeout = const Duration(seconds: 5)}) async {
    lastBudgetsFromCache = false;
    try {
      final network = await fetchBudgets().timeout(timeout);
      // Persist fresh copy for offline
      // cache save (fire-and-forget)
      // ignore: unawaited_futures
      LocalBudgetStore.save(network);
      return network;
    } catch (_) {
      final cached = await LocalBudgetStore.load();
      lastBudgetsFromCache = true;
      return cached;
    }
  }


  //create Budget start
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
          late final Budget created;
          if (res.body.isNotEmpty) {
            final map = jsonDecode(res.body) as Map<String, dynamic>;
            created =  Budget.fromJson(map);
          } else {
            // Success without body → synthesize from payload + Location header if present
            final loc = res.headers['location'];
            final id = (loc != null && loc.trim().isNotEmpty)
                ? loc.split('/').last
                : DateTime.now().millisecondsSinceEpoch.toString();
            created =  Budget(
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
          // 👇 NEW: optimistic cache update so Dashboard/Budgets see it immediately
          () async {
            final list = await LocalBudgetStore.load();
            final withoutDupes = list.where((b) => b.id != created.id).toList();
            withoutDupes.add(created);
            await LocalBudgetStore.save(withoutDupes);
          }();

          return created;
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
//create Budget end

  //update Budget start
  Future<Budget> updateBudget({
    required String id,
    required BudgetKind kind,
    required String currency,
    required double amount,
    int? year,
    int? month,
    String? tripId,
    String? name,
    String? linkedMonthlyBudgetId,
  }) async {
    final payload = {
      'id': id,
      'kind': kind == BudgetKind.monthly ? 'monthly' : 'trip',
      'currency': currency,
      'amount': amount,
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (tripId != null) 'tripId': tripId,
      if (name != null) 'name': name,
      if (linkedMonthlyBudgetId != null) 'linkedMonthlyBudgetId': linkedMonthlyBudgetId,
    };

    final endpoints = <({String method, String url})>[
      (method: 'PUT', url: '$baseUrl/budgets/$id'),
      (method: 'PATCH', url: '$baseUrl/budgets/$id'),
      (method: 'POST', url: '$baseUrl/budgets/$id'), // some APIs accept POST for update
      (method: 'PUT', url: '$baseUrl/budget/$id'),
    ];

    Exception? lastError;
    for (final e in endpoints) {
      try {
        final uri = Uri.parse(e.url);
        final res = await (
            e.method == 'PUT' ? http.put(uri, headers: _headers(jsonBody: true), body: jsonEncode(payload)) :
            e.method == 'PATCH' ? http.patch(uri, headers: _headers(jsonBody: true), body: jsonEncode(payload)) :
            http.post(uri, headers: _headers(jsonBody: true), body: jsonEncode(payload))
        );
        if (res.statusCode == 200) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final updated = Budget.fromJson(map);
          // 👇 NEW
          () async {
            final list = await LocalBudgetStore.load();
            final next = list.where((b) => b.id != updated.id).toList()..add(updated);
            await LocalBudgetStore.save(next);
          }();
          return updated;
        }
        if (res.statusCode == 204 || (res.statusCode == 201 && res.body.isEmpty)) {
          // No body — synthesize from payload
          return Budget(
            id: id,
            kind: kind,
            currency: currency,
            amount: amount,
            year: year,
            month: month,
            tripId: tripId,
            name: name,
            linkedMonthlyBudgetId: linkedMonthlyBudgetId,
          );
        }
        if (res.statusCode != 404) {
          lastError = Exception('Update budget failed @ ${e.method} ${e.url}: ${res.statusCode} ${res.body}');
        }
      } catch (err) {
        lastError = Exception('Update budget error @ ${e.method} ${e.url}: $err');
      }
    }
    throw lastError ?? Exception('Update budget failed: endpoint not found');
  }

  // update budget end

  // delete Budget start
  Future<void> deleteBudget(String id) async {
    final attempts = <({String method, String url})>[
      (method: 'DELETE', url: '$baseUrl/budgets/$id'),
      (method: 'POST', url: '$baseUrl/budgets/$id/delete'),
      (method: 'DELETE', url: '$baseUrl/budget/$id'),
    ];
    Exception? lastError;
    for (final a in attempts) {
      try {
        final uri = Uri.parse(a.url);
        final res = await (
            a.method == 'DELETE' ? http.delete(uri, headers: _headers()) :
            http.post(uri, headers: _headers())
        );
        if (res.statusCode == 200 || res.statusCode == 202 || res.statusCode == 204) {
          // deleteBudget: inside the success branch (200/202/204):
          () async {
            final list = await LocalBudgetStore.load();
            await LocalBudgetStore.save(list.where((b) => b.id != id).toList());
          }();
          return;
        }
        if (res.statusCode != 404) {
          lastError = Exception('Delete budget failed @ ${a.method} ${a.url}: ${res.statusCode} ${res.body}');
        }
      } catch (err) {
        lastError = Exception('Delete budget error @ ${a.method} ${a.url}: $err');
      }
    }
    throw lastError ?? Exception('Delete budget failed: endpoint not found');
  }
// delete Budget end

// link Trip Budget start
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
  // link trip budget end

  // unlink Trip Budget start
  Future<void> unlinkTripBudget({required String tripBudgetId}) async {
    // Preferred endpoint
    var res = await http.post(
      Uri.parse('$baseUrl/budgets/$tripBudgetId/unlink'),
      headers: _headers(),
    );
    if (res.statusCode == 404) {
      // Legacy fallback: delete the link row by trip id
      res = await http.delete(
        Uri.parse('$baseUrl/budget-links/$tripBudgetId'),
        headers: _headers(),
      );
    }
    if (res.statusCode != 200 && res.statusCode != 204) {
      () async {
        final list = await LocalBudgetStore.load();
        final next = list.map((b) =>
        b.id == tripBudgetId ? b.copyWith(linkedMonthlyBudgetId: null) : b
        ).toList();
        await LocalBudgetStore.save(next);
      }();
      throw Exception('Unlink failed: ${res.statusCode} ${res.body}');
    }
  }
  // unlink trip budget end
}
