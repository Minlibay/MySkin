import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/api/backend_api.dart';

/// Where a product was seen / tapped. Mirrors the backend's allowed list
/// in `repos.dart` — keep in sync. Used by partner stats so they can tell
/// "people see this in the catalog but never in chat" type insights.
enum ProductSurface {
  catalog,
  recommendation,
  chat,
  shelf,
  scanResult,
  productDetail,
  favorites,
}

String _surfaceKey(ProductSurface s) => switch (s) {
      ProductSurface.catalog => 'catalog',
      ProductSurface.recommendation => 'recommendation',
      ProductSurface.chat => 'chat',
      ProductSurface.shelf => 'shelf',
      ProductSurface.scanResult => 'scan_result',
      ProductSurface.productDetail => 'product_detail',
      ProductSurface.favorites => 'favorites',
    };

enum ProductEventKind { impression, open, buyClick }

String _kindKey(ProductEventKind k) => switch (k) {
      ProductEventKind.impression => 'impression',
      ProductEventKind.open => 'open',
      ProductEventKind.buyClick => 'buy_click',
    };

/// Batched catalog interaction reporter. Single instance per app run.
///
/// - Generates a random `sessionKey` at construction so the backend can
///   dedup impressions per session (scrolling the same card past 5×
///   counts as one impression).
/// - Locally deduplicates impressions per session before they even leave
///   the device — saves network and stops the backend's unique index from
///   doing all the work on slow connections.
/// - Buffers events, flushes either on 20 items or after 4 seconds of
///   inactivity. Fire-and-forget — never blocks the UI, never throws.
class ProductTelemetry {
  ProductTelemetry(this._api);

  final BackendApi _api;

  final String sessionKey =
      List.generate(16, (_) => _rand.nextInt(16).toRadixString(16)).join();

  static final _rand = Random();

  static const _flushAfter = Duration(seconds: 4);
  static const _flushAtSize = 20;

  final List<Map<String, dynamic>> _queue = [];

  /// Impressions we've already reported this session — skip duplicates
  /// before they hit the wire. Key: 'productId:surface'.
  final Set<String> _seenImpressions = {};

  Timer? _flushTimer;

  void impression(String productId, ProductSurface surface) {
    final key = '$productId:${_surfaceKey(surface)}';
    if (!_seenImpressions.add(key)) return;
    _enqueue(productId, ProductEventKind.impression, surface);
  }

  void open(String productId, ProductSurface surface) {
    _enqueue(productId, ProductEventKind.open, surface);
  }

  void buyClick(String productId, ProductSurface surface) {
    _enqueue(productId, ProductEventKind.buyClick, surface);
  }

  void _enqueue(
      String productId, ProductEventKind kind, ProductSurface surface) {
    _queue.add({
      'product_id': productId,
      'kind': _kindKey(kind),
      'surface': _surfaceKey(surface),
      'session_key': sessionKey,
    });
    if (_queue.length >= _flushAtSize) {
      _flush();
    } else {
      _flushTimer?.cancel();
      _flushTimer = Timer(_flushAfter, _flush);
    }
  }

  Future<void> _flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_queue.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    try {
      await _api.logProductEvents(batch);
    } catch (e) {
      // Drop on failure — these aren't critical events worth retrying
      // and never want to risk piling them up forever.
      debugPrint('ProductTelemetry flush failed: $e');
    }
  }

  /// Flush any pending events immediately — call on logout / app pause to
  /// keep the latest activity visible to partners.
  Future<void> flush() => _flush();
}

/// App-wide provider. Lives for the whole session: the sessionKey stays
/// stable so impression dedup works across screens.
final productTelemetryProvider = Provider<ProductTelemetry>((ref) {
  return ProductTelemetry(ref.read(backendApiProvider));
});
