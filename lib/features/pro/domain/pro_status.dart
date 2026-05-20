/// Pro subscription state for the current user. Returned by
/// `GET /me/pro/status`. Source of truth is `proUntil` — a future
/// timestamp means active, null or past means free tier.
class ProStatus {
  const ProStatus({required this.isPro, this.proUntil});

  final bool isPro;
  final DateTime? proUntil;

  static const ProStatus free = ProStatus(isPro: false);

  factory ProStatus.fromJson(Map<String, dynamic> j) {
    final until = j['pro_until'];
    return ProStatus(
      isPro: (j['is_pro'] as bool?) ?? false,
      proUntil: until is String ? DateTime.tryParse(until)?.toLocal() : null,
    );
  }
}
