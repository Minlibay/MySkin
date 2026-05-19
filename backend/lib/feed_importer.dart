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
    this.volumeUnit,
    this.pictures = const [],
    this.params = const {},
    this.derivedTags = const [],
    this.derivedSkinTypes = const [],
    this.derivedIngredients = const [],
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
  final String? volumeUnit;
  final List<String> pictures;
  final Map<String, String> params;
  /// Concern tags derived from `Назначение` / `Тип кожи` params.
  final List<String> derivedTags;
  /// Skin types derived from `Тип кожи` ('all' / 'sensitive' when present).
  final List<String> derivedSkinTypes;
  /// INCI tags split out of the `Состав` param. Feed compositions are
  /// already comma-separated, so we just normalise to one ingredient per
  /// chip and let the admin curate.
  final List<String> derivedIngredients;
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

    final purpose = paramMap['Назначение'] ?? '';
    final skinTypeRaw = paramMap['Тип кожи'] ?? '';
    final derivedTags = _derivedTags(purpose, skinTypeRaw);
    final derivedSkin = _derivedSkinTypes(skinTypeRaw);
    final derivedIngredients =
        _splitIngredients(paramMap['Состав'] ?? '');

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
      // We deliberately leave the long-form `composition` empty when the
      // feed only carries an INCI list — that list belongs in
      // `ingredients` (chip tags), not the "О составе" prose block. The
      // long-form field stays available for admins to fill in editorial
      // notes about the formulation.
      composition: null,
      // Feed key is "Как использовать" — earlier guesses ("Применение")
      // never matched, so usage stayed empty. We also accept the
      // alternative names some partner feeds use.
      usage: _firstNonEmpty([
        paramMap['Как использовать'],
        paramMap['Способ применения'],
        paramMap['Применение'],
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
      volumeUnit: paramMap['Единица измерения'],
      pictures: pictures,
      params: paramMap,
      derivedTags: derivedTags,
      derivedSkinTypes: derivedSkin,
      derivedIngredients: derivedIngredients,
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

/// Maps a Russian-language `Назначение` (purpose) list — and a `Тип кожи`
/// hint — onto our canonical concern tag IDs (see taxonomy.dart). Returns
/// deduplicated tag IDs that pass our knownConcerns whitelist.
List<String> _derivedTags(String purpose, String skinType) {
  final hay = '${purpose.toLowerCase()} ${skinType.toLowerCase()}';
  if (hay.trim().isEmpty) return const [];
  final m = <String>{};
  void add(String tag, RegExp r) {
    if (r.hasMatch(hay)) m.add(tag);
  }

  add('dehydration', RegExp(r'увлажн'));
  add('dryness', RegExp(r'питан'));
  add('aging', RegExp(r'старен|возрастн|anti.?age'));
  add('wrinkles', RegExp(r'разглажив|морщин'));
  add('elasticity', RegExp(r'лифтинг|упруг|плотност'));
  add('acne', RegExp(r'против\s+несоверш|акне|воспал'));
  add('blackheads', RegExp(r'чёрн\w*\s+точ|чер\w*\s+точ|комедон'));
  add('pih', RegExp(r'постакне|пост-?акне|след\w*\s+от\s+акне'));
  add('pores', RegExp(r'пор\w*(\s+расш|\s+забит)|сужен\w*\s+пор'));
  add('oiliness', RegExp(r'матир|жирн\w*\s+блеск|себум'));
  add('pigmentation', RegExp(r'пигмент|выравнив\w*\s+тон'));
  add('dullness', RegExp(r'тускл|сиян'));
  add('redness', RegExp(r'покрасн'));
  add('rosacea', RegExp(r'купероз|розацеа'));
  add('sensitivity',
      RegExp(r'чувствительн|для\s+чувствительной|снятие\s+раздраж'));
  add('irritation',
      RegExp(r'успокаив|снятие\s+раздраж|раздражен|противовоспал'));
  add('puffiness', RegExp(r'отёчн|отечн|отек'));
  add('dark_circles', RegExp(r'тёмн\w*\s+круг|темн\w*\s+круг'));
  add('barrier', RegExp(r'восстановлен|барьер|защит\w*\s+барьер'));

  // Only allow tags from the canonical set (defensive — keeps drift in
  // check if someone adds a new rule but forgets the taxonomy entry).
  return m
      .where(knownConcernsLocal.contains)
      .toList(growable: false);
}

/// Mirrors backend.taxonomy.knownConcerns so feed_importer doesn't have to
/// import handlers (avoiding a circular dep). Keep in sync.
const Set<String> knownConcernsLocal = {
  'acne', 'blackheads', 'pih', 'pores',
  'oiliness', 'dryness', 'dehydration',
  'redness', 'rosacea', 'sensitivity', 'irritation',
  'aging', 'wrinkles', 'elasticity',
  'dullness', 'pigmentation', 'texture',
  'dark_circles', 'puffiness',
  'barrier', 'post_procedure',
};

/// Splits a free-form INCI composition string into individual ingredient
/// tags. Mirrors the admin form's paste-shortcut so feed-imported INCI
/// lists end up identical to manually pasted ones: comma / semicolon /
/// newline separators, trailing periods stripped, case-insensitive dedupe.
List<String> _splitIngredients(String raw) {
  if (raw.trim().isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final piece in raw.split(RegExp(r'[,;\n]+'))) {
    var t = piece.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.endsWith('.')) t = t.substring(0, t.length - 1).trim();
    if (t.isEmpty) continue;
    final key = t.toLowerCase();
    if (seen.add(key)) out.add(t);
  }
  return out;
}

List<String> _derivedSkinTypes(String raw) {
  final hay = raw.toLowerCase();
  if (hay.trim().isEmpty) return const [];
  final out = <String>{};
  if (hay.contains('для всех')) out.add('all');
  if (hay.contains('сухой')) out.add('dry');
  if (hay.contains('жирной')) out.add('oily');
  if (hay.contains('комбинирован')) out.add('combo');
  if (hay.contains('нормальной')) out.add('normal');
  return out.toList(growable: false);
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
