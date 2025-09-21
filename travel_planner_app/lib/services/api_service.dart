// api_service imports start
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
// api_service imports end

import 'package:shared_preferences/shared_preferences.dart';
// 👇 NEW: secure storage import
// api_service storage import start
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// api_service storage import end
import '../app_nav.dart';

import '../models/balance_row.dart';
import '../models/budget.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import 'local_budget_store.dart';
import 'dart:async';
import 'local_trip_store.dart';
import 'package:collection/collection.dart';
import '../models/monthly.dart';
import 'trip_storage_service.dart';
import 'fx_service.dart';
import '../models/monthly_txn.dart';
import './monthly_store.dart';

// 👇 NEW: storage instance + keys (place near top of file, after imports)
// api_service storage fields start
const _kJwtKey = 'auth_jwt';
const _kEmailKey = 'auth_email';
const _kUserIdKey = 'auth_userId';
final FlutterSecureStorage _secure = const FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
// api_service storage fields end

// --- Auth expiry tracking ---
Timer? _expiryTimer;
DateTime? _sessionExpiry;

Map<String, dynamic> _decodeJwtPayload(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return {};
    String normalized(String s) => s.padRight(s.length + (4 - s.length % 4) % 4, '=');
    final payload = utf8.decode(base64Url.decode(normalized(parts[1])));
    final map = (jsonDecode(payload) as Map).cast<String, dynamic>();
    return map;
  } catch (_) {
    return {};
  }
}

Duration? sessionRemaining() {
  if (_sessionExpiry == null) return null;
  final d = _sessionExpiry!.difference(DateTime.now());
  return d.isNegative ? Duration.zero : d;
}

// 👇 NEW: baseUrl that works on iOS/Android emulators & web
// baseUrl start
String get baseUrl {
  if (kIsWeb) return 'http://192.168.0.39:8080';
  if (Platform.isAndroid) return 'http://10.0.2.2:8080'; // Android emulator → host Mac
  return 'http://192.168.0.39:8080'; // iOS simulator / macOS
}
// baseUrl end

// 👇 UPDATE: store/clear JWT in secure storage whenever token changes
// setAuthToken start
String? _jwt;
void setAuthToken(String? token, {String? email, String? userId}) async {
  // cancel any previous timer
  _expiryTimer?.cancel();
  _sessionExpiry = null;

  _jwt = token;
  if (_jwt != null && _jwt!.isNotEmpty) {
    debugPrint('[Api] setAuthToken -> ${_jwt!.substring(0, 16)}...');

    // persist
    try {
      await _secure.write(key: _kJwtKey, value: _jwt);
      if (email != null) await _secure.write(key: _kEmailKey, value: email);
      if (userId != null) await _secure.write(key: _kUserIdKey, value: userId);
    } catch (_) {}

    // backward-compatible: also mirror to SharedPreferences for existing callers
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('api_jwt', _jwt!);
      if (email != null) await p.setString('user_email', email);
    } catch (_) {}

    // decode exp and schedule auto-logout
    final payload = _decodeJwtPayload(_jwt!);
    final exp = payload['exp'];
    if (exp is int) {
      _sessionExpiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true).toLocal();
      final delay = _sessionExpiry!.difference(DateTime.now());
      if (!delay.isNegative) {
        _expiryTimer = Timer(delay + const Duration(seconds: 1), () {
          debugPrint('[Auth] JWT expired — auto sign-out');
          _onAuthFailed();
        });
      }
    }
  } else {
    debugPrint('[Api] cleared auth token');
    try {
      await _secure.delete(key: _kJwtKey);
      await _secure.delete(key: _kEmailKey);
      await _secure.delete(key: _kUserIdKey);
    } catch (_) {}
    // mirror clear in SharedPreferences
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('api_jwt');
      await p.remove('user_email');
    } catch (_) {}
  }
}
// setAuthToken end

// 👇 NEW: shared headers ensuring Authorization: Bearer <jwt>
// _headers start
Map<String, String> _headers({Map<String, String>? extra}) {
  final h = <String, String>{
    'Accept': 'application/json',
  };
  if (_jwt != null && _jwt!.isNotEmpty) {
    h['Authorization'] = 'Bearer $_jwt';
  }
  if (extra != null) h.addAll(extra);
  return h;
}
// _headers end

class _FxCache {
  _FxCache(this.rate, this.ts);

  final double rate;
  final DateTime ts;
}

// --- Auth failure handler + HTTP guard ---
void _onAuthFailed() {
  _expiryTimer?.cancel();
  _sessionExpiry = null;
  _jwt = null;
  () async {
    try {
      await _secure.delete(key: _kJwtKey);
      await _secure.delete(key: _kEmailKey);
      await _secure.delete(key: _kUserIdKey);
      final p = await SharedPreferences.getInstance();
      await p.remove('api_jwt');
      await p.remove('user_email');
    } catch (_) {}
    navToSignIn();
  }();
}

void _guardAuthResponse(int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    debugPrint('[Auth] $statusCode received — forcing sign-out');
    _onAuthFailed();
  }
}

Future<http.Response> _sendWithGuard(Future<http.Response> future) async {
  final res = await future;
  _guardAuthResponse(res.statusCode);
  return res;
}

class ApiService {
  bool lastBudgetsFromCache = false;
  bool lastTripsFromCache = false;

// --- FX cache (1h TTL) ---
  final Map<String, _FxCache> _fx = {}; // key: 'FROM_TO'

  ApiService();

  // 👇 NEW: safe URL joiner — replaces '$baseUrl/...'
  // _u join start
  String _u(String path) {
    final b = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final p = path.replaceFirst(RegExp(r'^/+'), '');
    return '$b/$p';
  }
  // _u join end

  // 👇 NEW: hard gate — throws if token missing
  // _authHeadersRequired start
  Future<Map<String, String>> _authHeadersRequired() async {
    // Prefer in-memory token; if missing, attempt secure restore
    var token = _jwt;
    token ??= await _secure.read(key: _kJwtKey);
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated: missing auth token');
    }
    _jwt = token; // keep memory in sync
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
  // _authHeadersRequired end

  // 👇 NEW: await token before screens fire requests
  Future<void> waitForToken({Duration timeout = const Duration(seconds: 8)}) async {
    // Wait up to [timeout] for a token to appear in SharedPreferences.
    // Do not throw on timeout; callers can check presence separately.
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      // in-memory fast path
      if (_jwt != null && _jwt!.isNotEmpty) return;
      // secure storage fallback
      final saved = await _secure.read(key: _kJwtKey);
      if (saved != null && saved.isNotEmpty) {
        _jwt = saved;
        return;
      }
      // legacy mirror (in case some code still writes to SharedPreferences)
      try {
        final p = await SharedPreferences.getInstance();
        if ((p.getString('api_jwt') ?? '').isNotEmpty) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  // public helper for outbox
  Uri urlFor(String path) => Uri.parse(_u(path));

  // expose headers for outbox
  Future<Map<String, String>> headers(bool json) => _authHeadersRequired();

  // 👇 NEW: who am I — GET /auth/me to verify header + show user
  // getMe start
  Future<Map<String, dynamic>> getMe() async {
    final url = Uri.parse('${baseUrl}/auth/me');
    final res = await _sendWithGuard(http.get(url, headers: await _authHeadersRequired()));
    if (res.statusCode != 200) {
      throw Exception('GET /auth/me failed ${res.statusCode}: ${res.body}');
    }
    return (jsonDecode(res.body) as Map).cast<String, dynamic>();
  }
  // getMe end

  // 👇 NEW: exchange provider ID token for API JWT
  // loginWithIdToken start
  Future<void> loginWithIdToken({
    required String idToken,
    required String provider,
  }) async {
    final url = Uri.parse(_u('auth/$provider'));
    final res = await _sendWithGuard(http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    ));
    if (res.statusCode != 200) {
      throw Exception('Auth failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final jwt = data['jwt'] as String?;
    final email = data['email'] as String?;
    if (jwt != null) {
      setAuthToken(jwt, email: email);
    }
  }
  // loginWithIdToken end

  // Check for presence of a JWT in SharedPreferences.
  Future<bool> hasToken() async {
    if (_jwt != null && _jwt!.isNotEmpty) return true;
    final saved = await _secure.read(key: _kJwtKey);
    if (saved != null && saved.isNotEmpty) {
      _jwt = saved;
      return true;
    }
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getString('api_jwt') ?? '').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Validate current token by calling /auth/me. Clears token if invalid.
  Future<bool> validateToken() async {
    try {
      final url = Uri.parse(_u('auth/me'));
      final res = await _sendWithGuard(http.get(url, headers: await _authHeadersRequired()));
      if (res.statusCode == 200) return true;
    } catch (_) {
      // fall through to clear
    }
    setAuthToken(null);
    return false;
  }

  // 👇 NEW: dev login — POST /auth/dev and store jwt
  // loginDev start
  Future<void> loginDev({required String email}) async {
    final url = Uri.parse('${baseUrl}/auth/dev');
    final res = await _sendWithGuard(http.post(
      url,
      headers: _headers(extra: {'Content-Type': 'application/json'}),
      body: jsonEncode({'email': email}),
    ));
    if (res.statusCode != 200) {
      throw Exception('Dev auth failed ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final jwt = (body['jwt'] ?? body['token']) as String?;
    if (jwt == null || jwt.isEmpty) {
      throw Exception('Auth response missing jwt/token');
    }
    setAuthToken(jwt);
  }
  // loginDev end

  // 👇 NEW: restore session on app launch
  // restoreSession start
  Future<bool> restoreSession() async {
    final saved = await _secure.read(key: _kJwtKey);
    if (saved != null && saved.isNotEmpty) {
      _jwt = saved;
      debugPrint('[Api] restored token -> ${_jwt!.substring(0, 16)}...');
      // schedule expiry after restore as well
      setAuthToken(_jwt);
      return true;
    }
    return false;
  }
  // restoreSession end

  // 👇 NEW: convenience getter
  // isSignedIn start
  bool get isSignedIn => _jwt != null && _jwt!.isNotEmpty;
  // isSignedIn end

  // 👇 NEW: signOut — clears token + optional provider sign-outs
  // signOut start
  Future<void> signOut() async {
    try {
      // Optional: revoke Google session if you use google_sign_in
      // import 'package:google_sign_in/google_sign_in.dart'; at top if you enable this
      // await GoogleSignIn().signOut();
    } catch (_) {}
    // Apple Sign-In has no client-side persistent session to revoke.

    await _secure.delete(key: _kJwtKey);
    await _secure.delete(key: _kEmailKey);
    await _secure.delete(key: _kUserIdKey);
    // also clear SharedPreferences mirror
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('api_jwt');
      await p.remove('user_email');
    } catch (_) {}
    _jwt = null;
    debugPrint('[Api] signed out');
  }
  // signOut end

  // 👇 OPTIONAL: helper to login (dev) then fetch profile and persist userId/email
  // signInDevAndFetch start
  Future<void> signInDevAndFetch(String email) async {
    await loginDev(email: email);                 // uses your /auth/dev
    final me = await getMe();                     // calls /auth/me using the new jwt
    setAuthToken(_jwt, email: me['email'] as String?, userId: me['userId'] as String?);
  }
  // signInDevAndFetch end

  // -----------------------------
  // Trips
  // -----------------------------
  Future<List<Trip>> fetchTrips() async {
    final res = await _sendWithGuard(http.get(Uri.parse(_u('trips')), headers: await _authHeadersRequired()));
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
    final res = await _sendWithGuard(http.post(
      Uri.parse(_u('trips')),
      headers: await _authHeadersRequired(),
      body: jsonEncode(t.toJson()),
    ));
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    // include body for easier debugging
    throw Exception('Failed to create trip (${res.statusCode}) ${res.body}');
  }

  /// Create a lightweight group trip with just a name + base currency.
  /// Tries common REST variants and returns a Trip, synthesizing reasonable
  /// defaults if the backend returns a minimal payload.
  Future<Trip> createTripWithGroup({
    required String name,
    required String currency,
  }) async {
    final payload = {
      'name': name,
      'currency': currency.toUpperCase(),
    };

    final urls = <String>[
      _u('trips'),
      _u('api/trips'),
      _u('trip'),
    ];

    Exception? lastErr;
    http.Response? lastRes;
    for (final u in urls) {
      try {
        final res = await _sendWithGuard(http.post(
          Uri.parse(u),
          headers: await _authHeadersRequired(),
          body: jsonEncode(payload),
        ));
        lastRes = res;
        if (res.statusCode == 200 || res.statusCode == 201) {
          if (res.body.isNotEmpty) {
            try {
              final map = (jsonDecode(res.body) as Map).cast<String, dynamic>();
              // If backend returns a full Trip, use it; otherwise synthesize.
              if (map.containsKey('startDate') && map.containsKey('endDate') && map.containsKey('initialBudget')) {
                return Trip.fromJson(map);
              }
              final id = (map['id'] ?? map['tripId'] ?? map['uuid'] ?? '').toString();
              final participants = (map['participants'] as List?)?.cast<String>() ?? const <String>[];
              return Trip(
                id: id.isNotEmpty ? id : DateTime.now().millisecondsSinceEpoch.toString(),
                name: map['name']?.toString() ?? name,
                startDate: DateTime.now(),
                endDate: DateTime.now().add(const Duration(days: 3)),
                currency: (map['currency']?.toString() ?? currency).toUpperCase(),
                initialBudget: (map['initialBudget'] as num?)?.toDouble() ?? 0.0,
                participants: participants,
                spendCurrencies: const [],
              );
            } catch (_) {
              // fall through to synthesis below
            }
          }
          // Success without body — synthesize with Location header if present
          final loc = res.headers['location'];
          final id = (loc != null && loc.trim().isNotEmpty)
              ? loc.split('/').last
              : DateTime.now().millisecondsSinceEpoch.toString();
          return Trip(
            id: id,
            name: name,
            startDate: DateTime.now(),
            endDate: DateTime.now().add(const Duration(days: 3)),
            currency: currency.toUpperCase(),
            initialBudget: 0,
            participants: const [],
            spendCurrencies: const [],
          );
        }
        // keep trying alternate endpoints on 404
        if (res.statusCode != 404) {
          lastErr = Exception('Create group trip failed @ $u: ${res.statusCode} ${res.body}');
        }
      } catch (e) {
        lastErr = Exception('Create group trip error @ $u: $e');
      }
    }
    if (lastRes != null) {
      throw Exception('Create group trip failed: ${lastRes.statusCode} ${lastRes.body}');
    }
    throw lastErr ?? Exception('Create group trip failed: no endpoint available');
  }

  /// Join an existing trip using an invite token.
  Future<void> joinTrip(String tripId, String token) async {
    final attempts = <({String method, String url, bool useQuery})>[
      (method: 'POST', url: _u('trips/$tripId/join'), useQuery: false),
      (method: 'POST', url: _u('api/trips/$tripId/join'), useQuery: false),
      (method: 'GET',  url: _u('trips/$tripId/join'), useQuery: true),
    ];

    Exception? lastErr;
    for (final a in attempts) {
      try {
        final uri = a.useQuery
            ? Uri.parse(a.url).replace(queryParameters: {'token': token})
            : Uri.parse(a.url);
        final res = await _sendWithGuard(
          a.method == 'GET'
              ? http.get(uri, headers: await _authHeadersRequired())
              : http.post(uri, headers: await _authHeadersRequired(), body: jsonEncode({'token': token})),
        );
        if (res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 204) {
          return;
        }
        if (res.statusCode != 404) {
          lastErr = Exception('Join trip failed @ ${a.method} ${a.url}: ${res.statusCode} ${res.body}');
        }
      } catch (e) {
        lastErr = Exception('Join trip error @ ${a.method} ${a.url}: $e');
      }
    }
    throw lastErr ?? Exception('Join trip failed: endpoint not found');
  }

  Future<Trip> updateTrip(Trip t) async {
    final res = await _sendWithGuard(http.put(
      Uri.parse(_u('trips/${t.id}')),
      headers: await _authHeadersRequired(),
      body: jsonEncode(t.toJson()),
    ));
    if (res.statusCode != 200) {
      throw Exception('Failed to update trip (${res.statusCode}) ${res.body}');
    }
    return Trip.fromJson(jsonDecode(res.body));
  }

  Future<void> deleteTrip(String id) async {
    final res = await _sendWithGuard(http.delete(Uri.parse(_u('trips/$id')), headers: await _authHeadersRequired()));
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('Failed to delete trip (${res.statusCode}) ${res.body}');
    }
  }

  // -----------------------------
  // Expenses
  // -----------------------------
  Future<List<Expense>> fetchExpenses(String tripId) async {
    final res = await _sendWithGuard(http.get(
      Uri.parse(_u('expenses/$tripId')),
      headers: await _authHeadersRequired(),
    ));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Expense.fromJson(e)).toList();
    }
    throw Exception('Failed to load expenses (${res.statusCode})');
  }

  Future<void> addExpense(Expense e) async {
    final res = await _sendWithGuard(http.post(
      Uri.parse(_u('expenses')),
      headers: await _authHeadersRequired(),
      body: jsonEncode(e.toJson()),
    ));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to add expense (${res.statusCode})');
    }
  }

  Future<Expense> updateExpense(Expense e) async {
    final uri = Uri.parse(_u('expenses/${e.id}'));
    final res = await _sendWithGuard(http.put(uri, headers: await _authHeadersRequired(), body: jsonEncode(e.toJson())));
    if (res.statusCode != 200) {
      throw Exception('Failed to update expense (${res.statusCode}) ${res.body}');
    }
    return Expense.fromJson(jsonDecode(res.body));
  }


  Future<void> deleteExpense(String id) async {
    final res = await _sendWithGuard(http.delete(Uri.parse(_u('expenses/$id')), headers: await _authHeadersRequired()));
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('Failed to delete expense (${res.statusCode}) ${res.body}');
    }
  }


  // -----------------------------
  // Balances + Settle Up
  // -----------------------------
  Future<List<BalanceRow>> fetchGroupBalances(String tripId) async {
    // Prefer /balances/{tripId}; fallback to legacy /expenses/split/{tripId}
    var res = await _sendWithGuard(http.get(
      Uri.parse(_u('balances/$tripId')),
      headers: await _authHeadersRequired(),
    ));
    if (res.statusCode == 404) {
      res = await _sendWithGuard(http.get(
        Uri.parse(_u('expenses/split/$tripId')),
        headers: await _authHeadersRequired(),
      ));
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

    var res = await _sendWithGuard(http.post(
      Uri.parse(_u('balances/settle')),
      headers: await _authHeadersRequired(),
      body: jsonEncode(payload),
    ));

    // Fallback: legacy/alternate endpoint
    if (res.statusCode == 404) {
      res = await _sendWithGuard(http.post(
        Uri.parse(_u('settlements')),
        headers: await _authHeadersRequired(),
        body: jsonEncode(payload),
      ));
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
    final uri = Uri.parse(_u('currency/convert')).replace(
      queryParameters: {
        'from': from.toUpperCase(),
        'to': to.toUpperCase(),
        'amount': amount.toString(),
      },
    );
    final res = await _sendWithGuard(http.get(uri, headers: await _authHeadersRequired()));
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
    final res = await _sendWithGuard(http.get(
      Uri.parse(_u('budgets')),
      headers: await _authHeadersRequired(),
    ));
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
      _u('budgets'),
      if (kind == BudgetKind.monthly) _u('budgets/monthly') else _u('budgets/trip'),
      _u('budget'),
      if (kind == BudgetKind.monthly) _u('budget/monthly') else _u('budget/trip'),
      _u('api/budgets'),
      if (kind == BudgetKind.monthly) _u('api/budgets/monthly') else _u('api/budgets/trip'),
    ];

    Exception? lastError;

    for (final url in endpoints) {
      try {
        final res = await _sendWithGuard(http.post(
          Uri.parse(url),
          headers: await _authHeadersRequired(),
          body: jsonEncode(payload),
        ));

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

        // On 401/403: clear token and stop trying other endpoints
        if (res.statusCode == 401 || res.statusCode == 403) {
          setAuthToken(null);
          lastError = Exception('Unauthorized (${res.statusCode}). Please sign in again.');
          break;
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
      (method: 'PUT', url: _u('budgets/$id')),
      (method: 'PATCH', url: _u('budgets/$id')),
      (method: 'POST', url: _u('budgets/$id')), // some APIs accept POST for update
      (method: 'PUT', url: _u('budget/$id')),
    ];

    Exception? lastError;
    for (final e in endpoints) {
      try {
        final uri = Uri.parse(e.url);
        final res = await _sendWithGuard(
            e.method == 'PUT' ? http.put(uri, headers: await _authHeadersRequired(), body: jsonEncode(payload)) :
            e.method == 'PATCH' ? http.patch(uri, headers: await _authHeadersRequired(), body: jsonEncode(payload)) :
            http.post(uri, headers: await _authHeadersRequired(), body: jsonEncode(payload))
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
      (method: 'DELETE', url: _u('budgets/$id')),
      (method: 'POST', url: _u('budgets/$id/delete')),
      (method: 'DELETE', url: _u('budget/$id')),
    ];
    Exception? lastError;
    for (final a in attempts) {
      try {
        final uri = Uri.parse(a.url);
        final res = await _sendWithGuard(
            a.method == 'DELETE' ? http.delete(uri, headers: await _authHeadersRequired()) :
            http.post(uri, headers: await _authHeadersRequired())
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
    final res = await _sendWithGuard(http.post(
      Uri.parse(_u('budgets/$tripBudgetId/link')),
      headers: await _authHeadersRequired(),
      body: jsonEncode({'monthlyBudgetId': monthlyBudgetId}),
    ));
    if (res.statusCode == 404) {
      // Alternate legacy endpoint
      final res2 = await _sendWithGuard(http.post(
        Uri.parse(_u('budget-links')),
        headers: await _authHeadersRequired(),
        body: jsonEncode({
          'tripBudgetId': tripBudgetId,
          'monthlyBudgetId': monthlyBudgetId,
        }),
      ));
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
    var res = await _sendWithGuard(http.post(
      Uri.parse(_u('budgets/$tripBudgetId/unlink')),
      headers: await _authHeadersRequired(),
    ));
    if (res.statusCode == 404) {
      // Legacy fallback: delete the link row by trip id
      res = await _sendWithGuard(http.delete(
        Uri.parse(_u('budget-links/$tripBudgetId')),
        headers: await _authHeadersRequired(),
      ));
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

  // ---- Monthly helpers start ----
  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _endOfMonth(DateTime d)   => DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);

  /// Build EnvelopeVM list for the given month from:
  /// - Monthly budgets (kind=monthly, year/month match)
  /// - Trip budgets (kind=trip) that link to a monthly via linkedMonthlyBudgetId
  /// - Expenses under the linked tripIds, converted to the monthly currency and filtered to that month.
  Future<List<EnvelopeVM>> fetchMonthlyEnvelopes(DateTime month) async {
    final mm = _startOfMonth(month);
    final monthlyCurrencyFallback = TripStorageService.getHomeCurrency();
    // 1) load all budgets (server or cache)
    final budgets = await fetchBudgetsOrCache();
    final monthlies = budgets.where((b) =>
      b.kind == BudgetKind.monthly &&
      b.year == mm.year && b.month == mm.month).toList();

    // 2) for each monthly, find linked trip budgets
    final List<EnvelopeVM> out = [];
    int idx = 0;
    for (final m in monthlies) {
      final linkedTripBudgets = budgets.where((b) =>
        b.kind == BudgetKind.trip && b.linkedMonthlyBudgetId == m.id).toList();

      // collect tripIds
      final tripIds = linkedTripBudgets.map((t) => t.tripId).whereType<String>().toSet();

      // 3) sum expenses for those trips within the month, convert each to monthly currency
      final start = _startOfMonth(mm).toUtc();
      final end   = _endOfMonth(mm).toUtc();
      double spent = 0.0;

      for (final tripId in tripIds) {
        final expenses = await fetchExpenses(tripId);
        // choose a budget currency when an expense is missing a currency
        final defaultTripCcy = linkedTripBudgets.firstWhere((t) => t.tripId == tripId,
                                orElse: () => linkedTripBudgets.first).currency;
        for (final e in expenses) {
          final dt = e.date.toUtc();
          if (dt.isBefore(start) || dt.isAfter(end)) continue;
          final from = (e.currency.isEmpty ? defaultTripCcy : e.currency).toUpperCase();
          final to   = (m.currency.isEmpty ? monthlyCurrencyFallback : m.currency).toUpperCase();
          if (from == to) {
            spent += e.amount;
          } else {
            try { spent += await convert(amount: e.amount, from: from, to: to); }
            catch (_) { spent += e.amount; } // safe fallback
          }
        }
      }

      final name = (m.name?.isNotEmpty == true)
        ? m.name!
        : '${['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m.month ?? 0]} ${m.year ?? ''}';

      out.add(EnvelopeVM(
        id: m.id,
        name: name,
        currency: m.currency,
        planned: m.amount,
        spent: spent,
        colorIndex: idx++,
      ));
    }
    // Sort by most recent/descending budgeted by default
    out.sort((a,b) => b.planned.compareTo(a.planned));
    return out;
  }

  Future<MonthlyBudgetSummary> fetchMonthlySummary(DateTime month) async {
    final envs = await fetchMonthlyEnvelopes(month);
    final ccy = envs.isNotEmpty ? envs.first.currency : TripStorageService.getHomeCurrency();
    final totalPlanned = envs.fold<double>(0.0, (p, e) => p + e.planned);

    // Load month-local transactions and convert to monthly currency if needed
    final key = monthKeyOf(month);
    final txns = await MonthlyStore.all(key);

    double monthIncome = 0.0;
    double monthExpenses = 0.0;

    for (final t in txns) {
      final from = t.currency.toUpperCase();
      final to = ccy.toUpperCase();
      double v = t.amount;
      if (from != to) {
        try {
          v = await convert(amount: t.amount, from: from, to: to);
        } catch (_) {
          v = t.amount;
        }
      }
      if (t.kind == MonthlyTxnKind.income) {
        monthIncome += v;
      } else {
        monthExpenses += v;
      }
    }

    // Trip-linked spent is already inside fetchMonthlyEnvelopes() as env.spent
    final tripLinkedSpent = envs.fold<double>(0.0, (p, e) => p + e.spent);
    final totalSpent = tripLinkedSpent + monthExpenses;

    return MonthlyBudgetSummary(
      currency: ccy,
      totalBudgeted: totalPlanned,
      totalSpent: totalSpent,
      totalIncome: monthIncome,
      totalMonthExpenses: monthExpenses,
    );
  }
  // ---- Monthly helpers end ----

}
