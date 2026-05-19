/// Canonical vocabularies shared across the backend.
///
/// One source of truth so vision parsing, product validation, and the
/// recommendation ranker can't drift apart silently (e.g. "oiliness" in one
/// place and "oily" in another, which would just never match and noone
/// would notice).
library;

/// Skin-concern tags the GigaChat Vision prompt is allowed to emit and the
/// only tags products are allowed to be filed under for concern-based
/// matching. Anything outside this set is dropped on scan ingest and
/// rejected on partner product publish.
const Set<String> knownConcerns = {
  // Inflammatory / blemishes
  'acne',
  'blackheads',
  'pih',
  'pores',
  // Oil / hydration balance
  'oiliness',
  'dryness',
  'dehydration',
  // Reactivity
  'redness',
  'rosacea',
  'sensitivity',
  'irritation',
  // Aging
  'aging',
  'wrinkles',
  'elasticity',
  // Tone & texture
  'dullness',
  'pigmentation',
  'texture',
  // Eye area
  'dark_circles',
  'puffiness',
  // Barrier
  'barrier',
  'post_procedure',
};

/// Skin types the matcher recognises. `all` means "fits any type".
const Set<String> knownSkinTypes = {
  'dry',
  'oily',
  'combo',
  'normal',
  'all',
};

/// Quality_warnings that mean the photo can't be analysed at all — the
/// metrics would be meaningless, so we refuse to save the scan and ask the
/// user to retake. Anything else (lighting hints, distance hints) is
/// surfaced but doesn't block the save.
const Set<String> criticalScanWarnings = {
  'no_face_detected',
  'image_too_dark',
  'too_dark',
  'too_blurry',
  'too_far',
};
