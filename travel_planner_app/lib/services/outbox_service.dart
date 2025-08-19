import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// A queued REST operation when offline/unavailable.
/// We keep paths relative to ApiService.baseUrl, and JSON bodies as strings.
class OutboxOp {
  OutboxOp({
    required this.method, // 'POST' | 'PUT' | 'PATCH' | 'DELETE'
    required this.path,   // e.g. '/expenses', '/budgets/{id}'
    this.jsonBody,        // serialized JSON string (optional)
  });

  final String method;
  final String path;
  final String? jsonBody;

  Map<String, dynamic> toJson() => {
    'm': method,
    'p': path,
    if (jsonBody != null) 'b': jsonBody,
  };

  static OutboxOp fromJson(Map<String, dynamic> m) => OutboxOp(
    method: m['m'] as String,
    path: m['p'] as String,
    jsonBody: m['b'] as String?,
  );
}

class OutboxService {
  static const _k = 'outbox_v1';

  static Future<List<OutboxOp>> _load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k);
    if (s == null || s.isEmpty) return <OutboxOp>[];
    try {
      final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      return raw.map(OutboxOp.fromJson).toList();
    } catch (_) {
      return <OutboxOp>[];
    }
  }

  static Future<void> _save(List<OutboxOp> ops) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(ops.map((e) => e.toJson()).toList()));
  }

  static Future<int> count() async => (await _load()).length;

  /// Add a new operation to the queue.
  static Future<void> enqueue(OutboxOp op) async {
    final list = await _load();
    list.add(op);
    await _save(list);
  }

  /// Try to send everything in order. Stops on first hard failure (e.g. 4xx).
  /// Returns number of operations sent successfully.
  static Future<int> flush({
    required Uri Function(String path) urlFor,                // e.g. (p) => Uri.parse('$baseUrl$p')
    required Map<String, String> Function(bool json) headers, // e.g. api.headers
    Duration perRequestTimeout = const Duration(seconds: 7),
  }) async {
    var list = await _load();
    if (list.isEmpty) return 0;

    final sent = <int>[];
    for (var i = 0; i < list.length; i++) {
      final op = list[i];
      try {
        final uri = urlFor(op.path);
        final h = headers(true);
        http.Response res;
        switch (op.method) {
          case 'POST':
            res = await http.post(uri, headers: h, body: op.jsonBody).timeout(perRequestTimeout);
            break;
          case 'PUT':
            res = await http.put(uri, headers: h, body: op.jsonBody).timeout(perRequestTimeout);
            break;
          case 'PATCH':
            res = await http.patch(uri, headers: h, body: op.jsonBody).timeout(perRequestTimeout);
            break;
          case 'DELETE':
            res = await http.delete(uri, headers: h).timeout(perRequestTimeout);
            break;
          default:
            continue;
        }
        if (res.statusCode >= 200 && res.statusCode < 300) {
          sent.add(i);
        } else if (res.statusCode >= 500) {
          // transient – keep in queue, try later
          break;
        } else {
          // 4xx – probably a bad payload; drop it to unblock the queue
          sent.add(i);
        }
      } on SocketException {
        break;
      } on HttpException {
        break;
      } on TimeoutException {
        break;
      } catch (_) {
        break;
      }
    }

    if (sent.isNotEmpty) {
      // remove by index (from the end)
      sent.sort();
      for (var j = sent.length - 1; j >= 0; j--) {
        list.removeAt(sent[j]);
      }
      await _save(list);
    }
    return sent.length;
  }
}

