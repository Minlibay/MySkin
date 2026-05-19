/// YML (Yandex Market Language) feed parser tuned for advcake / Golden Apple
/// affiliate exports. Used by the admin import endpoint to bulk-create
/// catalog products from a partner feed.
///
/// We deliberately keep the parser dependency-light (xml package only) and
/// do all the field mapping in this file so the handler layer can stay thin.
library;

import 'package:xml/xml.dart';

/// One category entry from the feed's <categories> block. The feed mixes
/// skincare with cookware/jewellery/etc., so the admin UI shows this list
/// with offer counts so a human can pick the relevant subset.
class FeedCategory {
  FeedCategory({
    required this.id,
    required this.name,
    this.offerCount = 0,
  });
  final String id;
  final String name;
  int offerCount;
}

/// One <offer> parsed and normalised — what the importer hands to the DB
/// layer. Optional fields are null when the feed didn't carry them.
class FeedOffer {
  FeedOffer({
    required this.externalId,
    required this.name,
    required this.url,
    required this.priceRub,
    required this.brand,
    required this.categoryId,
    this.description,
    this.composition,
    this.usage,
    this.precautions,
    this.country,
    this.volume,
    this.pictures = const [],
    this.params = const {},
  });

  final String externalId;
  final String name;
  final String url;
  final int priceRub;
  final String brand;
  final String categoryId;
  final String? description;
  final String? composition;
  final String? usage;
  final String? precautions;
  final String? country;
  final String? volume;
  final List<String> pictures;
  final Map<String, String> params;
}

/// Top-level parsed feed view returned by [parseFeed] / [previewFeed].
class FeedSnapshot {
  FeedSnapshot({
    required this.categories,
    required this.offers,
  });
  final Map<String, FeedCategory> categories;
  final List<FeedOffer> offers;
}

/// Parse the entire YML document. Caller decides whether to keep all offers
/// or filter by [onlyCategoryIds]. We keep parsing in-memory simple — the
/// feeds we've seen are under 5 MB and well under 1000 offers.
FeedSnapshot parseFeed(String xml, {Set<String>? onlyCategoryIds}) {
  final doc = XmlDocument.parse(xml);
  final categories = <String, FeedCategory>{};
  for (final c in doc.findAllElements('category')) {
    final id = c.getAttribute('id') ?? '';
    if (id.isEmpty) continue;
    categories[id] =
        FeedCategory(id: id, name: c.innerText.trim());
  }

  final offers = <FeedOffer>[];
  for (final o in doc.findAllElements('offer')) {
    final externalId = o.getAttribute('id') ?? '';
    if (externalId.isEmpty) continue;
    final categoryId = _childText(o, 'categoryId') ?? '';
    if (onlyCategoryIds != null && !onlyCategoryIds.contains(categoryId)) {
      // Still bump the count so previews are accurate.
      categories[categoryId]?.offerCount++;
      continue;
    }
    final available = o.getAttribute('available') ?? 'true';
    if (available.toLowerCase() == 'false') continue;

    categories[categoryId]?.offerCount++;

    final paramMap = <String, String>{};
    for (final p in o.findElements('param')) {
      final name = p.getAttribute('name')?.trim();
      final value = p.innerText.trim();
      if (name == null || name.isEmpty || value.isEmpty) continue;
      paramMap[name] = value;
    }

    final name = _childText(o, 'name') ??
        _childText(o, 'model') ??
        paramMap['Наименование продукта от поставщика'] ??
        '';
    if (name.isEmpty) continue;

    final brand = _childText(o, 'vendor') ??
        paramMap['Бренд'] ??
        '';
    if (brand.isEmpty) continue;

    final url = _childText(o, 'url') ?? '';
    if (url.isEmpty) continue;

    final priceRub = _parsePrice(_childText(o, 'price'));
    if (priceRub == null) continue;

    final pictures = o
        .findElements('picture')
        .map((e) => e.innerText.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    offers.add(FeedOffer(
      externalId: externalId,
      name: _cleanText(name),
      url: url,
      priceRub: priceRub,
      brand: _cleanText(brand),
      categoryId: categoryId,
      description: _firstNonEmpty([
        paramMap['Описание товара'],
        _childText(o, 'description'),
      ]).maybeCleanHtml(),
      composition: _firstNonEmpty([paramMap['Состав']]).maybeCleanHtml(),
      usage: _firstNonEmpty([
        paramMap['Применение'],
        paramMap['Способ применения'],
        paramMap['Инструкция по применению'],
      ]).maybeCleanHtml(),
      precautions: _firstNonEmpty([
        paramMap['Меры предосторожности'],
        paramMap['Противопоказания'],
      ]).maybeCleanHtml(),
      country: _firstNonEmpty([
        _childText(o, 'country_of_origin'),
        paramMap['Страна бренда'],
      ]),
      volume: _firstNonEmpty([
        paramMap['Объем'],
        paramMap['Объём'],
      ]),
      pictures: pictures,
      params: paramMap,
    ));
  }

  return FeedSnapshot(categories: categories, offers: offers);
}

/// Cheap heuristic: maps a feed category name (or product name fallback) to
/// our canonical `kind` taxonomy. Returns null when nothing recognised —
/// admin can still fix that one product manually.
String? guessKind(String categoryName, String productName) {
  final hay = '$categoryName $productName'.toLowerCase();
  // Order matters: more specific tokens first (eye_patch before serum).
  const rules = [
    ('патч', 'eye_patch'),
    ('пэд', 'pad'),
    ('скраб', 'scrub'),
    ('пилинг', 'peeling'),
    ('маск', 'mask'),
    ('тоник', 'toner'),
    ('эссенц', 'essence'),
    ('сывор', 'serum'),
    ('eye cream', 'eye_cream'),
    ('крем для глаз', 'eye_cream'),
    ('спф', 'spf'),
    ('spf', 'spf'),
    ('защит', 'spf'),
    ('очищ', 'cleanser'),
    ('умыв', 'cleanser'),
    ('гель для умы', 'cleanser'),
    ('демакияж', 'cleanser'),
    ('крем', 'moisturizer'),
  ];
  for (final r in rules) {
    if (hay.contains(r.$1)) return r.$2;
  }
  return null;
}

String? _childText(XmlElement el, String name) {
  for (final c in el.findElements(name)) {
    final t = c.innerText.trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}

int? _parsePrice(String? raw) {
  if (raw == null) return null;
  final stripped = raw.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.');
  final n = double.tryParse(stripped);
  if (n == null || !n.isFinite) return null;
  return n.round();
}

String _cleanText(String s) {
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _firstNonEmpty(List<String?> xs) {
  for (final x in xs) {
    if (x != null && x.trim().isNotEmpty) return x.trim();
  }
  return null;
}

extension on String? {
  /// Strips simple HTML (br/p/span) from feed description fields. Feeds
  /// often embed `&lt;br/&gt;` entities — XML already decoded them, so we
  /// only need to strip the literal tags now.
  String? maybeCleanHtml() {
    if (this == null) return null;
    final s = this!;
    final stripped = s
        .replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?(p|div|span|strong|em|b|i)[^>]*>',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return stripped.isEmpty ? null : stripped;
  }
}
