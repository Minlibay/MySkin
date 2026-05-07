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
    );
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
