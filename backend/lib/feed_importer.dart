/// YML (Yandex Market Language) and CSV feed parser tuned for advcake /
/// Golden Apple affiliate exports. Used by the admin import endpoint to
/// bulk-create catalog products from a partner feed.
///
/// Advcake silently switched the same URL between XML and CSV at some
/// point, so [parseFeed] auto-detects the format from the document head:
/// `<?xml ` or `<yml_catalog` → XML; anything else (BOM + `id;name;…`
/// header) → CSV. Field mapping converges into the same FeedSnapshot.
library;

import 'package:csv/csv.dart';
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

/// Entry point — picks XML vs CSV by sniffing the first useful character
/// after the BOM. Caller decides whether to keep all offers or filter by
/// [onlyCategoryIds]; the filter accepts either real XML category ids
/// ("63") or CSV-style slugified names ("category-Сыворотки") that
/// [parseFeedCsv] generates.
FeedSnapshot parseFeed(String raw, {Set<String>? onlyCategoryIds}) {
  // Strip UTF-8 BOM if present — appears at the start of CSV exports.
  final body = raw.startsWith('﻿') ? raw.substring(1) : raw;
  final trimmedHead = body.trimLeft();
  final isXml = trimmedHead.startsWith('<?xml') ||
      trimmedHead.startsWith('<yml_catalog');
  if (!isXml) {
    return parseFeedCsv(body, onlyCategoryIds: onlyCategoryIds);
  }
  return _parseFeedXml(body, onlyCategoryIds: onlyCategoryIds);
}

FeedSnapshot _parseFeedXml(String xml, {Set<String>? onlyCategoryIds}) {
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

/// Maps a feed offer to our canonical `kind`. Three layers, strongest first:
///
///   1. **`Тип продукта` exact-prefix match** — the feed's product-type
///      param is a well-formed taxonomy ("крем для лица", "маски для лица",
///      "флюид для лица", …). When it's set we trust it absolutely. This
///      prevents misclassification when the product name accidentally
///      contains a competing token ("Mask Glow крем для лица" was previously
///      tagged `mask` because the rule for "маск" matched before "крем").
///
///   2. **Word-boundary regex** on the same string the strict layer missed,
///      then categoryName, then productName. Boundaries (`\b…\b`) avoid
///      "крем" matching inside "kremlin", "маск" matching inside "маскара",
///      etc.
///
///   3. Returns null → caller picks a default ('serum' in the importer).
String? guessKind(String categoryName, String productName,
    {String productType = ''}) {
  // Layer 1: strict productType mapping. Pulled from the actual feed dump.
  // Keys are lowercase, matched as startsWith so suffixes (volume, line)
  // don't trip the dictionary.
  const productTypeMap = <String, String>{
    'крем для лица': 'moisturizer',
    'крем-гель для лица': 'moisturizer',
    'крем-гель': 'moisturizer',
    'флюид для лица': 'moisturizer',
    'флюид': 'moisturizer',
    'эмульсия для лица': 'moisturizer',
    'эмульсия': 'moisturizer',
    'масло для лица': 'moisturizer',
    'крем для глаз': 'eye_cream',
    'сыворотка для глаз': 'eye_serum',
    'патчи для глаз': 'eye_patch',
    'патчи': 'eye_patch',
    'маски для лица': 'mask',
    'маски': 'mask',
    'тканевые маски': 'mask',
    'сыворотка для лица': 'serum',
    'сыворотка': 'serum',
    'эссенция': 'essence',
    'тоник для лица': 'toner',
    'тоник': 'toner',
    'тонер': 'toner',
    'пэды': 'pad',
    'диски': 'pad',
    'скраб для лица': 'scrub',
    'скраб': 'scrub',
    'пилинг для лица': 'peeling',
    'пилинг': 'peeling',
    'средство для умывания': 'cleanser',
    'гель для умывания': 'cleanser',
    'пенка для умывания': 'cleanser',
    'мусс для умывания': 'cleanser',
    'мицеллярная вода': 'cleanser',
    'средство для демакияжа': 'cleanser',
    'санскрин': 'spf',
    'солнцезащитный крем': 'spf',
    'крем с spf': 'spf',
  };
  final pt = productType.toLowerCase().trim();
  if (pt.isNotEmpty) {
    for (final entry in productTypeMap.entries) {
      if (pt.startsWith(entry.key)) return entry.value;
    }
  }

  // Layer 2: word-boundary regex over the remaining signals. Order matters
  // (more specific patterns first) — "крем для глаз" before "крем", etc.
  // Boundaries kill the false-positive where "маска" matched in "маскара".
  const rules = <(String, String)>[
    (r'крем\s+для\s+глаз', 'eye_cream'),
    (r'сыворотка\s+для\s+глаз', 'eye_serum'),
    (r'eye\s+cream', 'eye_cream'),
    (r'\bпатч\w*', 'eye_patch'),
    (r'\bпэд\w*|тонер[- ]пэд', 'pad'),
    (r'\bскраб\w*', 'scrub'),
    (r'\bпилинг\w*', 'peeling'),
    (r'\bмаск[аиу]\b|\bмаски\b|тканев\w+\s+маск', 'mask'),
    (r'\bтоник\w*|\bтонер\w*', 'toner'),
    (r'\bэссенц\w*', 'essence'),
    (r'\bсыворот\w*', 'serum'),
    (r'\bspf\b|санскрин|солнцезащит', 'spf'),
    (r'\bочищ\w*|\bумыв\w*|демакияж', 'cleanser'),
    (r'крем-?гель\s+для\s+лица|крем\s+для\s+лица|\bкрем\w*\s+ночн|\bкрем\w*\s+дневн',
        'moisturizer'),
    (r'\bфлюид\w*|\bэмульсия\b|масло\s+для\s+лица', 'moisturizer'),
  ];
  // Same priority chain: productType → categoryName → productName.
  for (final source in [productType, categoryName, productName]) {
    if (source.isEmpty) continue;
    final hay = source.toLowerCase();
    for (final r in rules) {
      if (RegExp(r.$1).hasMatch(hay)) return r.$2;
    }
  }
  // Final fallback for "крем" tokens that didn't carry a "для лица" suffix —
  // try a loose "крем" match on the product name only, since category names
  // tend to be too vague ("Для лица" matches everything).
  final pn = productName.toLowerCase();
  if (RegExp(r'\bкрем\w*').hasMatch(pn) &&
      !RegExp(r'для\s+тела|для\s+рук|для\s+ног').hasMatch(pn)) {
    return 'moisturizer';
  }
  return null;
}

/// Returns true when the ingredients list contains any "active" worth
/// warning the user about — retinoids, exfoliating acids, high-dose vit C,
/// benzoyl peroxide, azelaic, hydroquinone. Niacinamide / hyaluronic /
/// ceramides are NOT treated as active in this sense — they're hydration
/// staples that don't carry the same combine-with-SPF caveat.
bool guessIsActive(List<String> ingredients) {
  if (ingredients.isEmpty) return false;
  // Substrings rather than exact tokens — INCI names have suffixes
  // (Retinyl Palmitate, Ascorbyl Glucoside, etc.).
  const triggers = [
    'retinol',
    'retinal',
    'retinaldehyde',
    'retinoic',
    'retinyl',
    'tretinoin',
    'adapalene',
    'bakuchiol', // retinol-adjacent, photosensitising claims
    'salicylic',
    'glycolic',
    'lactic acid',
    'mandelic',
    'malic acid',
    'tartaric',
    'azelaic',
    'benzoyl peroxide',
    'hydroquinone',
    'ascorbic acid',
    'l-ascorbic',
    'ascorbyl glucoside',
    'ascorbyl phosphate',
    'ethyl ascorbic',
    'tetrahexyldecyl ascorbate',
  ];
  final hay = ingredients.join(' | ').toLowerCase();
  for (final t in triggers) {
    if (hay.contains(t)) return true;
  }
  return false;
}

/// Returns true when the offer carries an SPF claim somewhere we can
/// recognise. Used to spare BB/CC creams and tinted moisturisers from the
/// makeup blocklist below — they technically count as makeup but their
/// SPF makes them part of the daily skincare ritual.
bool hasSpfClaim(FeedOffer offer) {
  if ((offer.params['SPF'] ?? '').trim().isNotEmpty) return true;
  final hay = [
    offer.name,
    offer.params['Тип продукта'] ?? '',
    offer.params['Назначение'] ?? '',
    offer.description ?? '',
  ].join(' ').toLowerCase();
  return RegExp(r'\bspf\s*\d|\bспф\s*\d|солнцезащит|с\s+защитой\s+от\s+солнц')
      .hasMatch(hay);
}

/// Returns true when the offer's primary purpose is decorative makeup
/// rather than skincare. Most makeup is filtered by this; BB/CC creams
/// and tinted SPF products that overlap with skincare are NOT flagged
/// here because the caller checks `hasSpfClaim` first.
bool isMakeupCategory(FeedOffer offer) {
  final pt = (offer.params['Тип продукта'] ?? '').toLowerCase();
  const makeupTypes = [
    'тональный крем',
    'тональная основа',
    'тональное средство',
    'пудра',
    'румяна',
    'хайлайтер',
    'бронзер',
    'корректор',
    'консилер',
    'праймер',
    'базы под макияж',
    'фиксатор макияжа',
    'тени для век',
    'тушь для ресниц',
    'тушь',
    'подводка',
    'карандаш',
    'помада',
    'блеск для губ',
    'тинт',
    'лайнер для губ',
    'кисти для макияжа',
    'спонжи',
    'мерцающая пудра',
  ];
  if (makeupTypes.any(pt.contains)) return true;
  final name = offer.name.toLowerCase();
  const nameBlockers = [
    'тональный крем',
    'тональная основа',
    'foundation',
    'concealer',
    'консилер',
    'mascara',
    'тушь',
    'lipstick',
    'помада',
    'lip gloss',
    'блеск для губ',
    'eye shadow',
    'тени для век',
    'blush',
    'румяна',
  ];
  return nameBlockers.any(name.contains);
}

/// Returns true when the offer is for face / eye skincare — what we actually
/// want in the catalog. Filters out body / hand / feet / nail / lash / brow
/// products even when their Назначение happens to overlap with skincare
/// purposes ("увлажнение" applies just as well to body lotion).
///
/// Signal priority:
///   1. `Область применения` (face / body / nails / brows / lashes / lips
///      / neck-and-decollete). When set and free of "лицо" / "глаза", we
///      reject — body lotion with "лицо,тело" still passes because the
///      face is in the list.
///   2. `Тип продукта` explicit body categories ("крем для тела" etc.).
///   3. Product name keyword sweep for "для тела / рук / ног / волос".
bool isFaceProduct(FeedOffer offer) {
  final area = (offer.params['Область применения'] ?? '').toLowerCase();
  if (area.isNotEmpty) {
    // Face areas we consider in-scope. Anything outside this set with no
    // face/eye mention is rejected.
    const faceAreas = ['лицо', 'глаза'];
    final mentionsFace = faceAreas.any(area.contains);
    if (!mentionsFace) return false;
  }
  final pt = (offer.params['Тип продукта'] ?? '').toLowerCase();
  if (pt.isNotEmpty) {
    const nonFaceTypes = [
      'для тела',
      'для рук',
      'для ног',
      'для волос',
      'для ногтей',
      'для ресниц',
      'для бровей',
      'для губ',
    ];
    if (nonFaceTypes.any(pt.contains)) return false;
  }
  final name = offer.name.toLowerCase();
  const nameBlockers = [
    'для тела',
    'для рук',
    'для ног',
    'для волос',
    'body lotion',
    'hand cream',
    'foot cream',
  ];
  if (nameBlockers.any(name.contains)) return false;
  return true;
}

/// Returns true when the offer is meant for sensitive / reactive skin.
/// Signals:
///   - `Гипоаллергенно` param is "true"
///   - `Тип кожи` includes "для чувствительной"
///   - description / usage mentions "деликатн" / "успокаива" / "мягк"
bool guessGentle(Map<String, String> params,
    {String description = '', String usage = ''}) {
  final hypo = (params['Гипоаллергенно'] ?? '').toLowerCase();
  if (hypo == 'true' || hypo == 'да') return true;
  final skin = (params['Тип кожи'] ?? '').toLowerCase();
  if (skin.contains('чувствительной')) return true;
  final hay = '$description $usage'.toLowerCase();
  if (RegExp(r'деликатн|успокаива|мягк[оа]\s+очищ|для\s+чувствительной')
      .hasMatch(hay)) {
    return true;
  }
  return false;
}

/// Best-guess routine phase for a freshly imported product. SPF is always
/// morning by definition. Retinoids / exfoliating acids should default to
/// evening (UV-sensitivity). Otherwise we read time-of-day cues from the
/// usage / description; lacking those, fall back to `any`.
String guessRoutinePhase({
  required String kind,
  required bool isActive,
  String description = '',
  String usage = '',
}) {
  if (kind == 'spf') return 'morning';
  final hay = '$description $usage'.toLowerCase();
  final mentionsMorning =
      RegExp(r'утром|днём|днем|перед\s+выход').hasMatch(hay);
  final mentionsEvening =
      RegExp(r'вечером|на\s+ночь|перед\s+сном|ночн[ыо]').hasMatch(hay);
  if (mentionsMorning && !mentionsEvening) return 'morning';
  if (mentionsEvening && !mentionsMorning) return 'evening';
  // Photosensitising actives default to evening when the text didn't pick
  // a side. Same rule dermatologists apply to retinoids / AHA.
  if (isActive && !mentionsMorning) return 'evening';
  return 'any';
}

/// CSV path. The new advcake format is semicolon-separated with a single
/// header row and an inline `params` field that packs the old XML `<param>`
/// list as `key1:value1|key2:value2|…`. Embedded newlines inside the
/// params field are properly quoted, so we let the `csv` package handle
/// line splitting.
FeedSnapshot parseFeedCsv(String body, {Set<String>? onlyCategoryIds}) {
  final rows = const CsvToListConverter(
    fieldDelimiter: ';',
    textDelimiter: '"',
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(body);
  if (rows.isEmpty) {
    return FeedSnapshot(categories: {}, offers: const []);
  }
  final header = rows.first.map((c) => '$c'.trim().toLowerCase()).toList();
  int idx(String name) => header.indexOf(name);
  final iId = idx('id');
  final iName = idx('name');
  final iCategory = idx('category');
  final iPrice = idx('price');
  final iUrl = idx('url');
  final iImage = idx('image');
  final iBrand = idx('brand');
  final iAvail = idx('available');
  final iModel = idx('model');
  final iDesc = idx('description');
  final iParams = idx('params');

  final categories = <String, FeedCategory>{};
  final offers = <FeedOffer>[];

  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.isEmpty) continue;
    String cell(int i) => i >= 0 && i < row.length ? '${row[i]}' : '';

    final externalId = cell(iId).trim();
    if (externalId.isEmpty) continue;

    // Availability gate. Advcake uses "in stock" / "out of stock"; rows
    // with empty avail come from continuation lines of a previous record
    // that broke our split heuristic — skip them.
    final avail = cell(iAvail).trim().toLowerCase();
    if (avail.isEmpty) continue;
    if (avail != 'in stock' && avail != 'true') continue;

    final categoryName = cell(iCategory).trim();
    // Stable id derived from the category label since CSV doesn't carry
    // numeric ids. Same name → same id across runs, so admin's stored
    // selections survive re-imports.
    final categoryId = categoryName.isEmpty
        ? 'uncategorised'
        : 'cat-${_slugify(categoryName)}';
    categories.putIfAbsent(categoryId,
        () => FeedCategory(id: categoryId, name: categoryName));

    if (onlyCategoryIds != null && !onlyCategoryIds.contains(categoryId)) {
      categories[categoryId]!.offerCount++;
      continue;
    }
    categories[categoryId]!.offerCount++;

    final paramMap = _parseInlineParams(cell(iParams));

    final name = _firstNonEmpty([
          cell(iName),
          cell(iModel),
          paramMap['Наименование продукта от поставщика'],
        ]) ??
        '';
    if (name.isEmpty) continue;

    final brand = _firstNonEmpty([
          cell(iBrand),
          paramMap['Бренд'],
        ]) ??
        '';
    if (brand.isEmpty) continue;

    final url = cell(iUrl).trim();
    if (url.isEmpty) continue;

    final priceRub = _parsePrice(cell(iPrice));
    if (priceRub == null) continue;

    final picture = cell(iImage).trim();
    final pictures = picture.isEmpty ? const <String>[] : [picture];

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
        cell(iDesc),
      ]).maybeCleanHtml(),
      composition: null,
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
      country: paramMap['Страна бренда'],
      volume: paramMap['Объем'] ?? paramMap['Объём'],
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

/// Splits the inline `params` cell into a key→value map. Format is
/// pipe-separated entries with the first colon as the key/value boundary.
/// Values may legitimately contain colons (URLs, "Тип:" prose), so we
/// split on FIRST colon only.
Map<String, String> _parseInlineParams(String raw) {
  if (raw.isEmpty) return const {};
  final out = <String, String>{};
  for (final piece in raw.split('|')) {
    final i = piece.indexOf(':');
    if (i <= 0) continue;
    final key = piece.substring(0, i).trim();
    final value = piece.substring(i + 1).trim();
    if (key.isEmpty || value.isEmpty) continue;
    out[key] = value;
  }
  return out;
}

String _slugify(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zа-яё0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
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
/// tags. Mirrors the admin form's paste-shortcut: comma / semicolon /
/// newline separators, trailing periods stripped, case-insensitive dedupe.
///
/// Also drops "label:value" style pieces — feed compositions for makeup
/// brushes and tools look like "Ворс:натурон,премиальная коза.
/// Феррул:латунь" which produces nonsense chips like "Ворс:натурон". Real
/// INCI names never contain a colon, so any piece with one is a label
/// pair, not an ingredient.
List<String> _splitIngredients(String raw) {
  if (raw.trim().isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final piece in raw.split(RegExp(r'[,;\n]+'))) {
    var t = piece.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.endsWith('.')) t = t.substring(0, t.length - 1).trim();
    if (t.isEmpty) continue;
    if (t.contains(':')) continue; // label:value, not an ingredient
    if (t.length > 80) continue; // descriptive sentence, not an INCI name
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
  /// Strips simple HTML (br/p/span) from feed description fields and trims
  /// the dangling half-sentence the source feed routinely truncates at
  /// (e.g. "Помогает визуально выров"). If the cleaned text doesn't end
  /// on a sentence terminator (. ! ? …), we look backwards for the last
  /// terminator and cut everything past it — losing the partial tail but
  /// keeping all complete sentences before it. No terminator anywhere
  /// means we leave the text as-is (safer than blanking a one-liner).
  String? maybeCleanHtml() {
    if (this == null) return null;
    final s = this!;
    var stripped = s
        .replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?(p|div|span|strong|em|b|i)[^>]*>',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    stripped = _trimDanglingSentence(stripped);
    return stripped.isEmpty ? null : stripped;
  }
}

String _trimDanglingSentence(String s) {
  if (s.isEmpty) return s;
  const terminators = {'.', '!', '?', '…'};
  if (terminators.contains(s[s.length - 1])) return s;
  for (var i = s.length - 1; i >= 0; i--) {
    if (terminators.contains(s[i])) {
      return s.substring(0, i + 1).trimRight();
    }
  }
  return s;
}
