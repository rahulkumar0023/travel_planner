import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uni_links/uni_links.dart';

/// Parsed information from an invite deep link.
class JoinInvite {
  JoinInvite({required this.tripId, required this.token, required this.raw});

  final String tripId;
  final String token;
  final String raw;
}

/// Centralises parsing and buffering of deep links so widgets can react
/// without worrying about platform timing or duplicate listeners.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  final _pending = <JoinInvite>[];
  final _controller = StreamController<JoinInvite>.broadcast();
  StreamSubscription<Uri?>? _sub;
  bool _listening = false;

  Stream<JoinInvite> get joinStream => _controller.stream;

  /// Consume the oldest buffered invite (typically from the initial launch).
  JoinInvite? takePendingJoin() {
    if (_pending.isEmpty) return null;
    return _pending.removeAt(0);
  }

  /// Start listening for incoming deep links. Safe to call multiple times.
  Future<void> ensureStarted() async {
    if (_listening) return;
    _listening = true;

    try {
      final initial = await getInitialUri();
      await _handleUri(initial);
    } catch (err) {
      if (kDebugMode) {
        // Surface parsing issues during development without crashing the app.
        debugPrint('DeepLinkService: initial URI error $err');
      }
    }

    _sub = uriLinkStream.listen(
      (uri) => _handleUri(uri),
      onError: (Object err) {
        if (kDebugMode) {
          debugPrint('DeepLinkService: stream error $err');
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _listening = false;
  }

  Future<void> _handleUri(Uri? uri) async {
    if (uri == null) return;
    final invite = _parseInvite(uri);
    if (invite == null) return;
    _pending.add(invite);
    if (!_controller.isClosed) {
      _controller.add(invite);
    }
  }

  JoinInvite? _parseInvite(Uri uri) {
    if (!uri.hasAuthority && !uri.hasScheme) return null;
    final segments = uri.pathSegments;

    // Pattern: https://host/trips/<id>/join?token=XYZ
    if (segments.length >= 3 &&
        segments[0].toLowerCase() == 'trips' &&
        segments[2].toLowerCase() == 'join') {
      final tripId = segments[1];
      final token = uri.queryParameters['token']?.trim() ?? '';
      if (tripId.isNotEmpty && token.isNotEmpty) {
        return JoinInvite(tripId: tripId, token: token, raw: uri.toString());
      }
    }

    // Pattern: https://host/invite?tripId=...&token=...
    final lowerPath = uri.path.toLowerCase();
    if (lowerPath.contains('invite')) {
      final tripId = uri.queryParameters['tripId'] ??
          uri.queryParameters['tripID'] ??
          uri.queryParameters['trip_id'] ??
          '';
      final token =
          uri.queryParameters['token'] ?? uri.queryParameters['invite'] ?? '';
      if (tripId.isNotEmpty && token.isNotEmpty) {
        return JoinInvite(tripId: tripId, token: token, raw: uri.toString());
      }
    }

    return null;
  }
}
