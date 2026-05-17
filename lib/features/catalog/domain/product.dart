import 'package:flutter/material.dart';

/// Skincare product as returned by /catalog and /catalog/:slug.
class Product {
  const Product({
    required this.id,
    required this.slug,
    required this.brand,
    required this.name,
    required this.kind,
    required this.description,
    required this.priceRub,
    required this.accentColor,
    required this.ingredients,
    required this.tags,
    required this.skinTypes,
    required this.isActive,
    required this.gentle,
    required this.routinePhase,
    this.matchScore,
    this.matchReasons = const [],
    this.shelfStatus,
    this.hasPhoto = false,
    this.status = 'published',
    this.isFavorite = false,
    this.photoSlots = const [],
    this.buyUrl,
    this.composition,
    this.precautions,
    this.usage,
    this.extraInfo,
    this.isCustom = false,
    this.fillLevel,
    this.openedAt,
    this.expiresAt,
    this.paoMonths,
  });

  final String id;
  final String slug;
  final String brand;
  final String name;
  final String kind;
  final String description;
  final int priceRub;
  final Color accentColor;
  final List<String> ingredients;
  final List<String> tags;
  final List<String> skinTypes;
  final bool isActive;
  final bool gentle;
  final String routinePhase;

  /// Personalised match (0..100). Only present when fetched while logged in.
  final int? matchScore;
  final List<String> matchReasons;

  /// Status from user_products if loaded as a shelf item.
  final String? shelfStatus;

  /// True if backend has a photo blob for this product.
  final bool hasPhoto;

  /// 'draft' | 'published'. Mobile only sees published, but kept here for completeness.
  final String status;

  /// True if the current user has bookmarked this product. Only meaningful on
  /// product-detail responses — list endpoints don't currently surface it.
  final bool isFavorite;

  /// Slot numbers (1..4) where the admin has uploaded photos. Empty list
  /// means the product has no photos yet; one slot means single classic
  /// photo. Only present on /catalog/<slug> detail responses.
  final List<int> photoSlots;

  /// External "Купить" URL for the in-app CTA. When null the button is
  /// hidden — works as a graceful fallback for legacy/admin-managed
  /// products that aren't owned by a partner.
  final String? buyUrl;

  /// Long-form product copy filled in by the partner (or admin). All four
  /// are optional — empty sections hide in the detail screen, and Лина
  /// only sees them when they have content.
  final String? composition;
  final String? precautions;
  final String? usage;
  final String? extraInfo;

  /// True when the product was added by the user themselves (not in the
  /// public catalog). Custom products live in `user_custom_products` server
  /// side and are visible only to the owner.
  final bool isCustom;

  /// Bottle fill level reported by the user: full | half | low | empty.
  final String? fillLevel;

  /// When the user opened the bottle. Combined with [paoMonths] to compute
  /// effective expiry. Null when unknown.
  final DateTime? openedAt;

  /// Hard expiry printed on the package.
  final DateTime? expiresAt;

  /// Period-after-opening in months (the "12M" / "6M" symbol on the label).
  final int? paoMonths;

  /// Effective expiry = min(expiresAt, openedAt + paoMonths). Null when no
  /// date info is available.
  DateTime? get effectiveExpiry {
    DateTime? paoEnd;
    if (openedAt != null && paoMonths != null) {
      final d = openedAt!;
      paoEnd = DateTime(d.year, d.month + paoMonths!, d.day);
    }
    if (expiresAt == null) return paoEnd;
    if (paoEnd == null) return expiresAt;
    return expiresAt!.isBefore(paoEnd) ? expiresAt : paoEnd;
  }

  /// Status bucket for UI: ok | expiring_soon | expired. Null when no expiry
  /// info is set.
  String? get expiryStatus {
    final e = effectiveExpiry;
    if (e == null) return null;
    final days = e.difference(DateTime.now()).inDays;
    if (days < 0) return 'expired';
    if (days <= 30) return 'expiring_soon';
    return 'ok';
  }

  factory Product.fromJson(Map<String, dynamic> j) {
    Color parseColor(String hex) {
      final v = hex.replaceAll('#', '');
      final n = int.parse(v, radix: 16);
      return Color(0xFF000000 | n);
    }

    return Product(
      id: j['id'] as String,
      slug: j['slug'] as String,
      brand: j['brand'] as String,
      name: j['name'] as String,
      kind: j['kind'] as String,
      description: j['description'] as String? ?? '',
      priceRub: (j['price_rub'] as num).toInt(),
      accentColor: parseColor(j['accent_color'] as String? ?? '#D98FA3'),
      ingredients:
          ((j['ingredients'] as List?) ?? const []).cast<String>(),
      tags: ((j['tags'] as List?) ?? const []).cast<String>(),
      skinTypes:
          ((j['skin_types'] as List?) ?? const []).cast<String>(),
      isActive: j['is_active'] as bool? ?? false,
      gentle: j['gentle'] as bool? ?? false,
      routinePhase: j['routine_phase'] as String? ?? 'any',
      matchScore: (j['match_score'] as num?)?.toInt(),
      matchReasons:
          ((j['match_reasons'] as List?) ?? const []).cast<String>(),
      // For shelf items the API returns user_product status ('have'|'wishlist'|
      // 'finished') in `status` and the product status is irrelevant. For
      // catalog items we get the publish status.
      shelfStatus: const {'have', 'wishlist', 'finished'}
              .contains(j['status'] as String?)
          ? j['status'] as String?
          : null,
      hasPhoto: j['has_photo'] as bool? ?? false,
      status: j['status'] is String &&
              !const {'have', 'wishlist', 'finished'}
                  .contains(j['status'] as String?)
          ? j['status'] as String
          : 'published',
      isFavorite: j['is_favorite'] as bool? ?? false,
      photoSlots:
          ((j['photo_slots'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      buyUrl: (j['buy_url'] as String?)?.trim().isNotEmpty == true
          ? (j['buy_url'] as String).trim()
          : null,
      composition: _stringOrNull(j['composition']),
      precautions: _stringOrNull(j['precautions']),
      usage: _stringOrNull(j['usage']),
      extraInfo: _stringOrNull(j['extra_info']),
      isCustom: j['is_custom'] as bool? ?? false,
      fillLevel: _stringOrNull(j['fill_level']),
      openedAt: _dateOrNull(j['opened_at']),
      expiresAt: _dateOrNull(j['expires_at']),
      paoMonths: (j['pao_months'] as num?)?.toInt(),
    );
  }

  static DateTime? _dateOrNull(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    if (t.isEmpty) return null;
    return DateTime.tryParse(t);
  }

  static String? _stringOrNull(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  String get kindLabel => switch (kind) {
        'cleanser' => 'Очищение',
        'toner' => 'Тоник',
        'essence' => 'Эссенция',
        'serum' => 'Сыворотка',
        'moisturizer' => 'Крем',
        'spf' => 'Защита SPF',
        'mask' => 'Маска',
        'eye_cream' => 'Крем для глаз',
        _ => kind,
      };
}
