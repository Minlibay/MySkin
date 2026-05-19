import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class UserRow {
  UserRow({
    required this.id,
    required this.phone,
    required this.createdAt,
    this.lastLoginAt,
    required this.isBlocked,
  });
  final String id;
  final String phone;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool isBlocked;

  Map<String, dynamic> toAdminJson() => {
        'id': id,
        'phone': phone,
        'created_at': createdAt.toUtc().toIso8601String(),
        'last_login_at': lastLoginAt?.toUtc().toIso8601String(),
        'is_blocked': isBlocked,
      };

  Map<String, dynamic> toClientJson() => {
        'id': id,
        'phone': phone,
      };

  static UserRow fromRow(List<dynamic> r) => UserRow(
        id: r[0] as String,
        phone: r[1] as String,
        createdAt: r[2] as DateTime,
        lastLoginAt: r[3] as DateTime?,
        isBlocked: r[4] as bool,
      );
}

class UserRepository {
  UserRepository(this.db);
  final Pool db;

  Future<UserRow> findOrCreateByPhone(String phone) async {
    final existing = await db.execute(
      Sql.named(
          'SELECT id, phone, created_at, last_login_at, is_blocked FROM users WHERE phone = @phone'),
      parameters: {'phone': phone},
    );
    if (existing.isNotEmpty) return UserRow.fromRow(existing.first);

    final id = _uuid.v4();
    final inserted = await db.execute(
      Sql.named(
          'INSERT INTO users (id, phone) VALUES (@id, @phone) RETURNING id, phone, created_at, last_login_at, is_blocked'),
      parameters: {'id': id, 'phone': phone},
    );
    return UserRow.fromRow(inserted.first);
  }

  Future<void> markLogin(String userId) async {
    await db.execute(
      Sql.named('UPDATE users SET last_login_at = now() WHERE id = @id'),
      parameters: {'id': userId},
    );
  }

  Future<UserRow?> findById(String id) async {
    final r = await db.execute(
      Sql.named(
          'SELECT id, phone, created_at, last_login_at, is_blocked FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    if (r.isEmpty) return null;
    return UserRow.fromRow(r.first);
  }

  Future<Map<String, dynamic>> getSettings(String id) async {
    final r = await db.execute(
      Sql.named('SELECT settings FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    if (r.isEmpty) return const {};
    final raw = r.first[0];
    if (raw is Map) return raw.cast<String, dynamic>();
    return const {};
  }

  Future<({List<int> bytes, String mime})?> getAvatar(String id) async {
    final r = await db.execute(
      Sql.named('SELECT avatar, avatar_mime FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    if (r.isEmpty || r.first[0] == null) return null;
    return (
      bytes: r.first[0] as List<int>,
      mime: (r.first[1] as String?) ?? 'image/jpeg',
    );
  }

  Future<void> setAvatar({
    required String id,
    required List<int> bytes,
    required String mime,
  }) async {
    await db.execute(
      Sql.named(
          'UPDATE users SET avatar = @b, avatar_mime = @m WHERE id = @id'),
      parameters: {
        'id': id,
        'b': TypedValue(Type.byteArray, Uint8List.fromList(bytes)),
        'm': mime,
      },
    );
  }

  Future<void> removeAvatar(String id) async {
    await db.execute(
      Sql.named(
          'UPDATE users SET avatar = NULL, avatar_mime = NULL WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  Future<bool> hasAvatar(String id) async {
    final r = await db.execute(
      Sql.named(
          'SELECT 1 FROM users WHERE id = @id AND avatar IS NOT NULL'),
      parameters: {'id': id},
    );
    return r.isNotEmpty;
  }

  Future<void> setSettings(String id, Map<String, dynamic> settings) async {
    await db.execute(
      Sql.named('UPDATE users SET settings = @s::jsonb WHERE id = @id'),
      parameters: {'id': id, 's': jsonEncode(settings)},
    );
  }

  Future<void> deleteAccount(String id) async {
    // Cascades to sessions, skin_profiles, routines, derm_sessions,
    // user_products, routine_completions.
    await db.execute(
      Sql.named('DELETE FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  Future<Map<String, dynamic>> exportData(String id) async {
    final user = await db.execute(
      Sql.named('''
        SELECT id, phone, created_at, last_login_at, settings
        FROM users WHERE id = @id
      '''),
      parameters: {'id': id},
    );
    if (user.isEmpty) return {'error': 'not_found'};
    final u = user.first;

    final profile = await db.execute(
      Sql.named('''
        SELECT name, skin_type, pores, concerns, acne_type, sensitivity,
               sensitivity_reaction, budget, extras, updated_at
        FROM skin_profiles WHERE user_id = @id
      '''),
      parameters: {'id': id},
    );

    final routines = await db.execute(
      Sql.named('''
        SELECT id, kind, payload, confidence, created_at
        FROM routines WHERE user_id = @id ORDER BY created_at DESC
      '''),
      parameters: {'id': id},
    );

    final shelfRows = await db.execute(
      Sql.named('''
        SELECT p.slug, p.brand, p.name, up.status, up.added_at
        FROM user_products up JOIN products p ON p.id = up.product_id
        WHERE up.user_id = @id ORDER BY up.added_at DESC
      '''),
      parameters: {'id': id},
    );

    final completions = await db.execute(
      Sql.named('''
        SELECT day, phase, step_index, step_title, completed_at
        FROM routine_completions WHERE user_id = @id ORDER BY day DESC
      '''),
      parameters: {'id': id},
    );

    return {
      'user': {
        'id': u[0],
        'phone': u[1],
        'created_at': (u[2] as DateTime).toUtc().toIso8601String(),
        'last_login_at':
            (u[3] as DateTime?)?.toUtc().toIso8601String(),
        'settings': u[4],
      },
      'profile': profile.isEmpty
          ? null
          : {
              'name': profile.first[0],
              'skin_type': profile.first[1],
              'pores': profile.first[2],
              'concerns': profile.first[3],
              'acne_type': profile.first[4],
              'sensitivity': profile.first[5],
              'sensitivity_reaction': profile.first[6],
              'budget': profile.first[7],
              'extras': profile.first[8],
              'updated_at':
                  (profile.first[9] as DateTime).toUtc().toIso8601String(),
            },
      'routines': routines
          .map((r) => {
                'id': r[0],
                'kind': r[1],
                'payload': r[2],
                'confidence': r[3],
                'created_at':
                    (r[4] as DateTime).toUtc().toIso8601String(),
              })
          .toList(),
      'shelf': shelfRows
          .map((r) => {
                'slug': r[0],
                'brand': r[1],
                'name': r[2],
                'status': r[3],
                'added_at': (r[4] as DateTime).toUtc().toIso8601String(),
              })
          .toList(),
      'completions': completions
          .map((r) => {
                'day': (r[0] as DateTime).toUtc().toIso8601String(),
                'phase': r[1],
                'step_index': r[2],
                'step_title': r[3],
                'completed_at':
                    (r[4] as DateTime).toUtc().toIso8601String(),
              })
          .toList(),
    };
  }

  Future<void> setBlocked(String id, bool blocked) async {
    await db.execute(
      Sql.named('UPDATE users SET is_blocked = @b WHERE id = @id'),
      parameters: {'id': id, 'b': blocked},
    );
  }

  Future<({List<UserRow> items, int total})> page({
    int limit = 20,
    int offset = 0,
    String? query,
  }) async {
    final hasQuery = query != null && query.trim().isNotEmpty;
    final filter = hasQuery ? "WHERE phone ILIKE '%' || @q || '%'" : '';
    final pageParams = {
      if (hasQuery) 'q': query.trim(),
      'limit': limit,
      'offset': offset,
    };
    final countParams = {if (hasQuery) 'q': query.trim()};
    final rows = await db.execute(
      Sql.named('''
        SELECT id, phone, created_at, last_login_at, is_blocked
        FROM users $filter
        ORDER BY created_at DESC
        LIMIT @limit OFFSET @offset
      '''),
      parameters: pageParams,
    );
    final totalRow = await db.execute(
      Sql.named('SELECT COUNT(*)::int FROM users $filter'),
      parameters: countParams,
    );
    return (
      items: rows.map(UserRow.fromRow).toList(),
      total: totalRow.first[0] as int,
    );
  }
}

class SessionRepository {
  SessionRepository(this.db);
  final Pool db;

  Future<String> create(String userId, {String? userAgent}) async {
    final token = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO sessions (token, user_id, user_agent, expires_at)
        VALUES (@t, @u, @ua, now() + INTERVAL '90 days')
      '''),
      parameters: {'t': token, 'u': userId, 'ua': userAgent},
    );
    return token;
  }

  Future<UserRow?> userForToken(String token) async {
    final r = await db.execute(
      Sql.named('''
        SELECT u.id, u.phone, u.created_at, u.last_login_at, u.is_blocked
        FROM sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.token = @t AND s.expires_at > now()
      '''),
      parameters: {'t': token},
    );
    if (r.isEmpty) return null;
    return UserRow.fromRow(r.first);
  }

  Future<void> delete(String token) async {
    await db.execute(
      Sql.named('DELETE FROM sessions WHERE token = @t'),
      parameters: {'t': token},
    );
  }
}

class OtpRepository {
  OtpRepository(this.db);
  final Pool db;

  /// Returns true if there's an active code issued less than 60s ago — used
  /// to throttle resend.
  Future<bool> hasFreshCode(String phone) async {
    final r = await db.execute(
      Sql.named('''
        SELECT 1 FROM otp_codes
        WHERE phone = @p AND expires_at > now() AND created_at > now() - INTERVAL '60 seconds'
      '''),
      parameters: {'p': phone},
    );
    return r.isNotEmpty;
  }

  Future<void> upsert({
    required String phone,
    required String codeHash,
    required String codePlain,
    required Duration ttl,
    required bool smsSent,
  }) async {
    await db.execute(
      Sql.named('''
        INSERT INTO otp_codes (phone, code_hash, code_plain, sms_sent,
                               expires_at, attempts, created_at)
        VALUES (@p, @h, @cp, @ss,
                now() + (@s::text || ' seconds')::interval, 0, now())
        ON CONFLICT (phone) DO UPDATE
          SET code_hash = EXCLUDED.code_hash,
              code_plain = EXCLUDED.code_plain,
              sms_sent = EXCLUDED.sms_sent,
              expires_at = EXCLUDED.expires_at,
              attempts = 0,
              created_at = now()
      '''),
      parameters: {
        'p': phone,
        'h': codeHash,
        'cp': codePlain,
        'ss': smsSent,
        's': ttl.inSeconds.toString(),
      },
    );
  }

  Future<
      List<
          ({
            String phone,
            String code,
            bool smsSent,
            DateTime createdAt,
            DateTime expiresAt,
            int attempts,
          })>> listPending() async {
    final r = await db.execute(Sql.named('''
      SELECT phone, code_plain, sms_sent, created_at, expires_at, attempts
      FROM otp_codes
      WHERE code_plain IS NOT NULL AND expires_at > now()
      ORDER BY created_at DESC
    '''));
    return r
        .map((row) => (
              phone: row[0] as String,
              code: row[1] as String,
              smsSent: row[2] as bool,
              createdAt: row[3] as DateTime,
              expiresAt: row[4] as DateTime,
              attempts: row[5] as int,
            ))
        .toList();
  }

  Future<({String codeHash, DateTime expiresAt, int attempts})?> get(
      String phone) async {
    final r = await db.execute(
      Sql.named(
          'SELECT code_hash, expires_at, attempts FROM otp_codes WHERE phone = @p'),
      parameters: {'p': phone},
    );
    if (r.isEmpty) return null;
    return (
      codeHash: r.first[0] as String,
      expiresAt: r.first[1] as DateTime,
      attempts: r.first[2] as int,
    );
  }

  Future<void> incAttempts(String phone) async {
    await db.execute(
      Sql.named(
          'UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = @p'),
      parameters: {'p': phone},
    );
  }

  Future<void> delete(String phone) async {
    await db.execute(
      Sql.named('DELETE FROM otp_codes WHERE phone = @p'),
      parameters: {'p': phone},
    );
  }
}

class AppSettingsRepository {
  AppSettingsRepository(this.db);
  final Pool db;

  Future<String?> get(String key) async {
    final r = await db.execute(
      Sql.named('SELECT value FROM app_settings WHERE key = @k'),
      parameters: {'k': key},
    );
    if (r.isEmpty) return null;
    return r.first[0] as String?;
  }

  Future<Map<String, String>> getMany(List<String> keys) async {
    if (keys.isEmpty) return {};
    final r = await db.execute(
      Sql.named(
          'SELECT key, value FROM app_settings WHERE key = ANY(@ks::text[])'),
      parameters: {'ks': keys},
    );
    return {for (final row in r) row[0] as String: row[1] as String};
  }

  Future<void> set(String key, String value) async {
    await db.execute(
      Sql.named('''
        INSERT INTO app_settings (key, value, updated_at)
        VALUES (@k, @v, now())
        ON CONFLICT (key) DO UPDATE
          SET value = EXCLUDED.value, updated_at = now()
      '''),
      parameters: {'k': key, 'v': value},
    );
  }
}

class AdminRow {
  AdminRow({required this.id, required this.login, required this.passwordHash});
  final String id;
  final String login;
  final String passwordHash;
}

class AdminRepository {
  AdminRepository(this.db);
  final Pool db;

  Future<AdminRow?> findByLogin(String login) async {
    final r = await db.execute(
      Sql.named('SELECT id, login, password_hash FROM admins WHERE login = @l'),
      parameters: {'l': login},
    );
    if (r.isEmpty) return null;
    return AdminRow(
      id: r.first[0] as String,
      login: r.first[1] as String,
      passwordHash: r.first[2] as String,
    );
  }

  Future<void> upsert(
      {required String login, required String passwordHash}) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO admins (id, login, password_hash)
        VALUES (@id, @l, @h)
        ON CONFLICT (login) DO UPDATE SET password_hash = EXCLUDED.password_hash
      '''),
      parameters: {'id': id, 'l': login, 'h': passwordHash},
    );
  }

  Future<String> createSession(String adminId) async {
    final token = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO admin_sessions (token, admin_id, expires_at)
        VALUES (@t, @a, now() + INTERVAL '12 hours')
      '''),
      parameters: {'t': token, 'a': adminId},
    );
    return token;
  }

  Future<bool> isValidToken(String token) async {
    final r = await db.execute(
      Sql.named(
          'SELECT 1 FROM admin_sessions WHERE token = @t AND expires_at > now()'),
      parameters: {'t': token},
    );
    return r.isNotEmpty;
  }

  /// Returns the admin id behind a session token, or null if expired/unknown.
  /// Used by moderation endpoints that need to stamp `reviewed_by`.
  Future<String?> adminIdForToken(String token) async {
    final r = await db.execute(
      Sql.named(
          'SELECT admin_id FROM admin_sessions WHERE token = @t AND expires_at > now()'),
      parameters: {'t': token},
    );
    return r.isEmpty ? null : r.first[0] as String;
  }

  Future<void> markLogin(String adminId) async {
    await db.execute(
      Sql.named('UPDATE admins SET last_login_at = now() WHERE id = @id'),
      parameters: {'id': adminId},
    );
  }

  Future<String?> passwordHashFor(String adminId) async {
    final r = await db.execute(
      Sql.named('SELECT password_hash FROM admins WHERE id = @id'),
      parameters: {'id': adminId},
    );
    return r.isEmpty ? null : r.first[0] as String;
  }

  Future<void> setPassword(String adminId, String passwordHash) async {
    await db.execute(
      Sql.named('UPDATE admins SET password_hash = @h WHERE id = @id'),
      parameters: {'h': passwordHash, 'id': adminId},
    );
  }
}

class PartnerRow {
  PartnerRow({
    required this.id,
    required this.login,
    required this.companyName,
    this.contactEmail,
    this.contactPhone,
    this.note,
    required this.isBlocked,
    required this.createdAt,
    this.lastLoginAt,
  });
  final String id;
  final String login;
  final String companyName;
  final String? contactEmail;
  final String? contactPhone;
  final String? note;
  final bool isBlocked;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  /// Shape used by the partner's own SPA — no internal flags exposed.
  Map<String, dynamic> toClientJson() => {
        'id': id,
        'login': login,
        'company_name': companyName,
        'contact_email': contactEmail,
        'contact_phone': contactPhone,
      };

  /// Shape used by the admin panel — sees everything.
  Map<String, dynamic> toAdminJson() => {
        'id': id,
        'login': login,
        'company_name': companyName,
        'contact_email': contactEmail,
        'contact_phone': contactPhone,
        'note': note,
        'is_blocked': isBlocked,
        'created_at': createdAt.toUtc().toIso8601String(),
        'last_login_at': lastLoginAt?.toUtc().toIso8601String(),
      };
}

class PartnerRepository {
  PartnerRepository(this.db);
  final Pool db;

  Future<PartnerRow?> findById(String id) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, login, company_name, contact_email, contact_phone, note,
               is_blocked, created_at, last_login_at
        FROM partners WHERE id = @id
      '''),
      parameters: {'id': id},
    );
    return r.isEmpty ? null : _fromRow(r.first);
  }

  Future<PartnerRow?> findByLogin(String login) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, login, company_name, contact_email, contact_phone, note,
               is_blocked, created_at, last_login_at
        FROM partners WHERE login = @l
      '''),
      parameters: {'l': login},
    );
    return r.isEmpty ? null : _fromRow(r.first);
  }

  Future<String> passwordHashFor(String partnerId) async {
    final r = await db.execute(
      Sql.named('SELECT password_hash FROM partners WHERE id = @id'),
      parameters: {'id': partnerId},
    );
    return r.isEmpty ? '' : r.first[0] as String;
  }

  Future<PartnerRow> create({
    required String login,
    required String passwordHash,
    required String companyName,
    String? contactEmail,
    String? contactPhone,
    String? note,
  }) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO partners
          (id, login, password_hash, company_name, contact_email,
           contact_phone, note)
        VALUES (@id, @l, @h, @cn, @ce, @cp, @n)
      '''),
      parameters: {
        'id': id,
        'l': login,
        'h': passwordHash,
        'cn': companyName,
        'ce': contactEmail,
        'cp': contactPhone,
        'n': note,
      },
    );
    return (await findById(id))!;
  }

  Future<void> setPassword(String partnerId, String passwordHash) async {
    await db.execute(
      Sql.named('UPDATE partners SET password_hash = @h WHERE id = @id'),
      parameters: {'h': passwordHash, 'id': partnerId},
    );
  }

  Future<void> setBlocked(String partnerId, bool blocked) async {
    await db.execute(
      Sql.named('UPDATE partners SET is_blocked = @b WHERE id = @id'),
      parameters: {'id': partnerId, 'b': blocked},
    );
  }

  Future<void> markLogin(String partnerId) async {
    await db.execute(
      Sql.named('UPDATE partners SET last_login_at = now() WHERE id = @id'),
      parameters: {'id': partnerId},
    );
  }

  Future<List<PartnerRow>> list({int limit = 200}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, login, company_name, contact_email, contact_phone, note,
               is_blocked, created_at, last_login_at
        FROM partners ORDER BY created_at DESC LIMIT @lim
      '''),
      parameters: {'lim': limit},
    );
    return r.map(_fromRow).toList();
  }

  Future<String> createSession(String partnerId,
      {String? userAgent}) async {
    final token = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO partner_sessions
          (token, partner_id, user_agent, expires_at)
        VALUES (@t, @p, @ua, now() + INTERVAL '12 hours')
      '''),
      parameters: {'t': token, 'p': partnerId, 'ua': userAgent},
    );
    return token;
  }

  Future<PartnerRow?> partnerForToken(String token) async {
    final r = await db.execute(
      Sql.named('''
        SELECT p.id, p.login, p.company_name, p.contact_email, p.contact_phone,
               p.note, p.is_blocked, p.created_at, p.last_login_at
        FROM partner_sessions s JOIN partners p ON p.id = s.partner_id
        WHERE s.token = @t AND s.expires_at > now()
      '''),
      parameters: {'t': token},
    );
    return r.isEmpty ? null : _fromRow(r.first);
  }

  Future<void> deleteSession(String token) async {
    await db.execute(
      Sql.named('DELETE FROM partner_sessions WHERE token = @t'),
      parameters: {'t': token},
    );
  }

  PartnerRow _fromRow(List<dynamic> r) => PartnerRow(
        id: r[0] as String,
        login: r[1] as String,
        companyName: r[2] as String,
        contactEmail: r[3] as String?,
        contactPhone: r[4] as String?,
        note: r[5] as String?,
        isBlocked: r[6] as bool,
        createdAt: r[7] as DateTime,
        lastLoginAt: r[8] as DateTime?,
      );
}

class BrandRow {
  BrandRow({
    required this.id,
    required this.name,
    required this.slug,
    this.ownerPartnerId,
    required this.status,
    this.moderationReason,
    this.submittedAt,
    this.reviewedAt,
    required this.createdAt,
  });
  final String id;
  final String name;
  final String slug;
  final String? ownerPartnerId;

  /// approved | pending | rejected
  final String status;
  final String? moderationReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'owner_partner_id': ownerPartnerId,
        'status': status,
        'moderation_reason': moderationReason,
        'submitted_at': submittedAt?.toUtc().toIso8601String(),
        'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

class BrandRepository {
  BrandRepository(this.db);
  final Pool db;

  static const _cols =
      'id, name::text, slug, owner_partner_id, status, moderation_reason, '
      'submitted_at, reviewed_at, created_at';

  Future<BrandRow?> findById(String id) async {
    final r = await db.execute(
      Sql.named('SELECT $_cols FROM brands WHERE id = @id'),
      parameters: {'id': id},
    );
    return r.isEmpty ? null : _fromRow(r.first);
  }

  Future<BrandRow?> findByName(String name) async {
    final r = await db.execute(
      Sql.named('SELECT $_cols FROM brands WHERE name = @n'),
      parameters: {'n': name},
    );
    return r.isEmpty ? null : _fromRow(r.first);
  }

  /// Lists brands. Filter by [ownerPartnerId] for the partner SPA, by
  /// [status] for the admin moderation queue, or pass nothing for "all".
  Future<List<BrandRow>> list({
    String? ownerPartnerId,
    String? status,
    int limit = 200,
  }) async {
    final where = <String>[];
    final params = <String, Object?>{'lim': limit};
    if (ownerPartnerId != null) {
      where.add('owner_partner_id = @owner');
      params['owner'] = ownerPartnerId;
    }
    if (status != null) {
      where.add('status = @st');
      params['st'] = status;
    }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final r = await db.execute(
      Sql.named(
          'SELECT $_cols FROM brands $w ORDER BY created_at DESC LIMIT @lim'),
      parameters: params,
    );
    return r.map(_fromRow).toList();
  }

  /// Creates a brand. Returns null if the name is already taken (case-
  /// insensitively — that's the CITEXT unique constraint doing its job).
  /// New brands from a partner come in as 'pending' and need admin review;
  /// brands created by admin can be passed [status]='approved' to skip the
  /// queue.
  Future<BrandRow?> create({
    required String name,
    required String slug,
    String? ownerPartnerId,
    required String status,
  }) async {
    try {
      final id = _uuid.v4();
      await db.execute(
        Sql.named('''
          INSERT INTO brands
            (id, name, slug, owner_partner_id, status, submitted_at)
          VALUES
            (@id, @n, @s, @o, @st,
             CASE WHEN @st = 'pending' THEN now() ELSE NULL END)
        '''),
        parameters: {
          'id': id,
          'n': name,
          's': slug,
          'o': ownerPartnerId,
          'st': status,
        },
      );
      return (await findById(id))!;
    } on ServerException catch (e) {
      // 23505 = unique_violation (either name or slug already taken).
      if (e.code == '23505') return null;
      rethrow;
    }
  }

  Future<void> setOwner(String brandId, String? partnerId) async {
    await db.execute(
      Sql.named(
          'UPDATE brands SET owner_partner_id = @o WHERE id = @id'),
      parameters: {'id': brandId, 'o': partnerId},
    );
  }

  Future<void> moderate({
    required String brandId,
    required String status, // 'approved' | 'rejected'
    String? reason,
    required String reviewerAdminId,
  }) async {
    await db.execute(
      Sql.named('''
        UPDATE brands
          SET status = @st,
              moderation_reason = @r,
              reviewed_at = now(),
              reviewed_by = @adm
        WHERE id = @id
      '''),
      parameters: {
        'id': brandId,
        'st': status,
        'r': reason,
        'adm': reviewerAdminId,
      },
    );
  }

  BrandRow _fromRow(List<dynamic> r) => BrandRow(
        id: r[0] as String,
        name: r[1] as String,
        slug: r[2] as String,
        ownerPartnerId: r[3] as String?,
        status: r[4] as String,
        moderationReason: r[5] as String?,
        submittedAt: r[6] as DateTime?,
        reviewedAt: r[7] as DateTime?,
        createdAt: r[8] as DateTime,
      );
}

/// Raw catalog interaction events from the mobile app. We never aggregate
/// at write time — partners see real numbers, the SQL does the work on
/// read. Impressions dedup per (product, session) via a partial unique
/// index, so scrolling the same card back and forth doesn't inflate counts.
class ProductEventRepository {
  ProductEventRepository(this.db);
  final Pool db;

  /// `shelf_add` lets us measure the conversion step between Лина's
  /// recommendation and the user actually committing to use the product —
  /// the most important data point for tuning the matcher.
  static const _validKinds = {
    'impression',
    'open',
    'buy_click',
    'shelf_add',
  };
  static const _validSurfaces = {
    'catalog',
    'recommendation',
    'chat',
    'shelf',
    'scan_result',
    'product_detail',
    'favorites',
  };

  /// Bulk-insert a batch coming from the client. Returns the count we
  /// actually wrote — duplicate impressions in the same session are
  /// silently dropped by the partial unique index.
  Future<int> insertBatch({
    required List<Map<String, dynamic>> events,
    required String? userId,
  }) async {
    if (events.isEmpty) return 0;
    var written = 0;
    // One statement per event keeps the code dumb and the ON CONFLICT
    // semantics simple. Volume here is tiny (a handful per scroll) — if it
    // ever isn't we can switch to COPY or a single multi-row insert.
    for (final e in events) {
      final productId = e['product_id'];
      final kind = e['kind'];
      final surface = e['surface'];
      final session = e['session_key'];
      if (productId is! String || productId.isEmpty) continue;
      if (kind is! String || !_validKinds.contains(kind)) continue;
      if (surface is! String || !_validSurfaces.contains(surface)) continue;
      try {
        final r = await db.execute(
          Sql.named('''
            INSERT INTO product_events
              (product_id, user_id, kind, surface, session_key)
            VALUES
              (@p, @u, @k, @s, @sk)
            ON CONFLICT DO NOTHING
          '''),
          parameters: {
            'p': productId,
            'u': userId,
            'k': kind,
            's': surface,
            'sk': session is String ? session : null,
          },
        );
        written += r.affectedRows;
      } catch (e) {
        // Foreign key violation (product_id no longer exists) — silently
        // skip rather than 500ing the whole batch.
      }
    }
    return written;
  }

  /// Per-product totals for a partner's drill-down screen. Filters on the
  /// time range; partner ownership is verified by the caller via the
  /// brand→partner join.
  Future<Map<String, dynamic>> productSummary({
    required String productId,
    required DateTime since,
  }) async {
    final r = await db.execute(
      Sql.named('''
        SELECT
          COUNT(*) FILTER (WHERE kind = 'impression')::int,
          COUNT(*) FILTER (WHERE kind = 'open')::int,
          COUNT(*) FILTER (WHERE kind = 'buy_click')::int,
          COUNT(*) FILTER (WHERE kind = 'shelf_add')::int,
          COUNT(DISTINCT user_id) FILTER (WHERE kind = 'open')::int
        FROM product_events
        WHERE product_id = @p AND created_at >= @since
      '''),
      parameters: {'p': productId, 'since': since},
    );
    final row = r.first;
    return {
      'impressions': row[0] as int,
      'opens': row[1] as int,
      'buy_clicks': row[2] as int,
      'shelf_adds': row[3] as int,
      'unique_openers': row[4] as int,
    };
  }

  /// Daily breakdown for the partner's chart. Returns one row per day in
  /// the range — including days with zero so the chart line stays continuous.
  Future<List<Map<String, dynamic>>> productDaily({
    required String productId,
    required DateTime since,
  }) async {
    final r = await db.execute(
      Sql.named('''
        WITH days AS (
          SELECT generate_series(@since::date, CURRENT_DATE, INTERVAL '1 day')::date AS day
        )
        SELECT
          d.day,
          COALESCE(SUM(CASE WHEN e.kind = 'impression' THEN 1 END), 0)::int,
          COALESCE(SUM(CASE WHEN e.kind = 'open' THEN 1 END), 0)::int,
          COALESCE(SUM(CASE WHEN e.kind = 'buy_click' THEN 1 END), 0)::int,
          COALESCE(SUM(CASE WHEN e.kind = 'shelf_add' THEN 1 END), 0)::int
        FROM days d
        LEFT JOIN product_events e
          ON e.product_id = @p
         AND e.created_at::date = d.day
        GROUP BY d.day
        ORDER BY d.day
      '''),
      parameters: {'p': productId, 'since': since},
    );
    return r
        .map((row) => {
              'day': (row[0] as DateTime).toIso8601String().substring(0, 10),
              'impressions': row[1] as int,
              'opens': row[2] as int,
              'buy_clicks': row[3] as int,
              'shelf_adds': row[4] as int,
            })
        .toList();
  }

  /// Top products for a partner across all their brands. `metric` selects
  /// which kind to sort by.
  Future<List<Map<String, dynamic>>> topForPartner({
    required String partnerId,
    required String metric, // impression | open | buy_click
    required DateTime since,
    int limit = 10,
  }) async {
    if (!_validKinds.contains(metric)) return const [];
    final r = await db.execute(
      Sql.named('''
        SELECT p.id, p.slug, p.name, b.name::text, COUNT(*)::int AS c
        FROM product_events e
        JOIN products p ON p.id = e.product_id
        JOIN brands b ON b.id = p.brand_id
        WHERE b.owner_partner_id = @partner
          AND e.kind = @kind
          AND e.created_at >= @since
        GROUP BY p.id, p.slug, p.name, b.name
        ORDER BY c DESC
        LIMIT @lim
      '''),
      parameters: {
        'partner': partnerId,
        'kind': metric,
        'since': since,
        'lim': limit,
      },
    );
    return r
        .map((row) => {
              'product_id': row[0] as String,
              'slug': row[1] as String,
              'name': row[2] as String,
              'brand': row[3] as String,
              'count': row[4] as int,
            })
        .toList();
  }
}

class StatsRepository {
  StatsRepository(this.db);
  final Pool db;

  Future<Map<String, dynamic>> overview() async {
    final users = await db.execute('SELECT COUNT(*)::int FROM users');
    final blocked =
        await db.execute('SELECT COUNT(*)::int FROM users WHERE is_blocked');
    final today = await db.execute('''
      SELECT COUNT(*)::int FROM users WHERE created_at::date = CURRENT_DATE
    ''');
    final sessions =
        await db.execute('SELECT COUNT(*)::int FROM sessions WHERE expires_at > now()');
    return {
      'users_total': users.first[0],
      'users_blocked': blocked.first[0],
      'users_today': today.first[0],
      'active_sessions': sessions.first[0],
    };
  }
}

/// JSON helper for repos that return jsonb.
dynamic toJsonb(Object? v) => v == null ? null : jsonEncode(v);

class ProductRow {
  ProductRow({
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
    this.status = 'draft',
    this.hasPhoto = false,
    this.buyUrl,
    this.moderationStatus = 'approved',
    this.moderationReason,
    this.submittedByPartnerId,
    this.composition,
    this.precautions,
    this.usage,
    this.extraInfo,
  });

  final String id;
  final String slug;
  final String brand;
  final String name;
  final String kind;
  final String description;
  final int priceRub;
  final String accentColor;
  final List<String> ingredients;
  final List<String> tags;
  final List<String> skinTypes;
  final bool isActive;
  final bool gentle;
  final String routinePhase;
  final String status; // draft | published
  final bool hasPhoto;
  final String? buyUrl;
  final String moderationStatus; // approved | pending | rejected
  final String? moderationReason;
  final String? submittedByPartnerId;
  final String? composition;
  final String? precautions;
  final String? usage;
  final String? extraInfo;

  static ProductRow fromRow(List<dynamic> r) {
    List<String> arr(int i) =>
        (r[i] as List? ?? const []).map((e) => '$e').toList();
    return ProductRow(
      id: r[0] as String,
      slug: r[1] as String,
      brand: r[2] as String,
      name: r[3] as String,
      kind: r[4] as String,
      description: r[5] as String,
      priceRub: r[6] as int,
      accentColor: r[7] as String,
      ingredients: arr(8),
      tags: arr(9),
      skinTypes: arr(10),
      isActive: r[11] as bool,
      gentle: r[12] as bool,
      routinePhase: r[13] as String,
      status: r.length > 14 ? (r[14] as String? ?? 'draft') : 'draft',
      hasPhoto: r.length > 15 ? (r[15] as bool? ?? false) : false,
      buyUrl: r.length > 16 ? r[16] as String? : null,
      moderationStatus:
          r.length > 17 ? (r[17] as String? ?? 'approved') : 'approved',
      moderationReason: r.length > 18 ? r[18] as String? : null,
      submittedByPartnerId: r.length > 19 ? r[19] as String? : null,
      composition: r.length > 20 ? r[20] as String? : null,
      precautions: r.length > 21 ? r[21] as String? : null,
      usage: r.length > 22 ? r[22] as String? : null,
      extraInfo: r.length > 23 ? r[23] as String? : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'brand': brand,
        'name': name,
        'kind': kind,
        'description': description,
        'price_rub': priceRub,
        'accent_color': accentColor,
        'ingredients': ingredients,
        'tags': tags,
        'skin_types': skinTypes,
        'is_active': isActive,
        'gentle': gentle,
        'routine_phase': routinePhase,
        'status': status,
        'has_photo': hasPhoto,
        'buy_url': buyUrl,
        'moderation_status': moderationStatus,
        'moderation_reason': moderationReason,
        'submitted_by_partner_id': submittedByPartnerId,
        'composition': composition,
        'precautions': precautions,
        'usage': usage,
        'extra_info': extraInfo,
      };
}

class ProductRepository {
  ProductRepository(this.db);
  final Pool db;

  static const _cols =
      'id, slug, brand, name, kind, description, price_rub, accent_color, '
      'ingredients, tags, skin_types, is_active_ingredient, gentle, '
      'routine_phase, status, photo IS NOT NULL, buy_url, moderation_status, '
      'moderation_reason, submitted_by_partner_id, composition, precautions, '
      'usage_instructions, extra_info';

  Future<List<ProductRow>> list({
    String? kind,
    String? concern,
    String? query,
    String? status,
    String? moderationStatus,
    String? submittedByPartnerId,
    bool publicCatalogOnly = false,
    int limit = 60,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'lim': limit,
      'off': offset,
    };
    final where = <String>[];
    if (kind != null && kind.isNotEmpty) {
      where.add('kind = @kind');
      params['kind'] = kind;
    }
    if (concern != null && concern.isNotEmpty) {
      where.add('tags @> @concern::jsonb');
      params['concern'] = jsonEncode([concern]);
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(name ILIKE @q OR brand ILIKE @q)');
      params['q'] = '%${query.trim()}%';
    }
    if (status != null && status.isNotEmpty) {
      where.add('status = @status');
      params['status'] = status;
    }
    if (moderationStatus != null && moderationStatus.isNotEmpty) {
      where.add('moderation_status = @mstatus');
      params['mstatus'] = moderationStatus;
    }
    if (submittedByPartnerId != null && submittedByPartnerId.isNotEmpty) {
      where.add('submitted_by_partner_id = @partner');
      params['partner'] = submittedByPartnerId;
    }
    if (publicCatalogOnly) {
      // Mobile catalog hides anything that isn't both published AND moderation-
      // approved — covers legacy admin-managed products (moderation_status
      // defaults to approved) and partner products only after admin sign-off.
      where.add("status = 'published'");
      where.add("moderation_status = 'approved'");
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.execute(
      Sql.named(
          'SELECT $_cols FROM products $clause ORDER BY brand, name LIMIT @lim OFFSET @off'),
      parameters: params,
    );
    return rows.map(ProductRow.fromRow).toList();
  }

  /// Create a new product on behalf of a partner. Lands in the moderation
  /// queue (`moderation_status='pending'`) and `status='draft'` so the
  /// mobile catalog never sees it before admin sign-off.
  Future<ProductRow?> createForPartner({
    required String partnerId,
    required String brandId,
    required String slug,
    required String brandName,
    required String name,
    required String kind,
    required String description,
    required int priceRub,
    required String accentColor,
    String? buyUrl,
    String routinePhase = 'any',
    bool gentle = false,
    bool isActive = false,
    List<String> tags = const [],
    List<String> skinTypes = const [],
    List<String> ingredients = const [],
    String? composition,
    String? precautions,
    String? usage,
    String? extraInfo,
  }) async {
    final id = _uuid.v4();
    try {
      await db.execute(
        Sql.named('''
          INSERT INTO products (
            id, slug, brand, name, kind, description, price_rub, accent_color,
            ingredients, tags, skin_types, is_active_ingredient, gentle,
            routine_phase, status, buy_url, brand_id, submitted_by_partner_id,
            moderation_status, submitted_at, composition, precautions,
            usage_instructions, extra_info
          ) VALUES (
            @id, @slug, @brand, @name, @kind, @desc, @price, @ac,
            @ing::jsonb, @tags::jsonb, @st::jsonb, @ai, @g, @rp, 'draft',
            @buy_url, @brand_id, @partner, 'pending', now(),
            @comp, @prec, @use, @extra
          )
        '''),
        parameters: {
          'id': id,
          'slug': slug,
          'brand': brandName,
          'name': name,
          'kind': kind,
          'desc': description,
          'price': priceRub,
          'ac': accentColor,
          'ing': jsonEncode(ingredients),
          'tags': jsonEncode(tags),
          'st': jsonEncode(skinTypes),
          'ai': isActive,
          'g': gentle,
          'rp': routinePhase,
          'buy_url': buyUrl,
          'brand_id': brandId,
          'partner': partnerId,
          'comp': composition,
          'prec': precautions,
          'use': usage,
          'extra': extraInfo,
        },
      );
      return findById(id);
    } on ServerException catch (e) {
      if (e.code == '23505') return null; // slug taken
      rethrow;
    }
  }

  /// Apply a patch from a partner. Caller must verify ownership first.
  /// Editing any product field resets moderation to pending so the admin
  /// re-reviews — straight-through edits would let a partner sneak content
  /// past moderation post-approval.
  Future<void> updateByPartner({
    required String productId,
    required Map<String, dynamic> patch,
  }) async {
    final existing = await findById(productId);
    if (existing == null) return;
    final patched = ProductRow(
      id: existing.id,
      slug: existing.slug,
      brand: existing.brand,
      name: (patch['name'] as String?) ?? existing.name,
      kind: (patch['kind'] as String?) ?? existing.kind,
      description:
          (patch['description'] as String?) ?? existing.description,
      priceRub:
          (patch['price_rub'] as num?)?.toInt() ?? existing.priceRub,
      accentColor:
          (patch['accent_color'] as String?) ?? existing.accentColor,
      ingredients: (patch['ingredients'] as List?)?.cast<String>() ??
          existing.ingredients,
      tags: (patch['tags'] as List?)?.cast<String>() ?? existing.tags,
      skinTypes: (patch['skin_types'] as List?)?.cast<String>() ??
          existing.skinTypes,
      isActive: existing.isActive,
      gentle: (patch['gentle'] as bool?) ?? existing.gentle,
      routinePhase:
          (patch['routine_phase'] as String?) ?? existing.routinePhase,
      status: 'draft',
      hasPhoto: existing.hasPhoto,
      buyUrl: patch.containsKey('buy_url')
          ? patch['buy_url'] as String?
          : existing.buyUrl,
    );
    // Long-form fields use patch.containsKey so passing null explicitly
    // clears them, while omitting the key keeps the prior value.
    final composition = patch.containsKey('composition')
        ? patch['composition'] as String?
        : existing.composition;
    final precautions = patch.containsKey('precautions')
        ? patch['precautions'] as String?
        : existing.precautions;
    final usage =
        patch.containsKey('usage') ? patch['usage'] as String? : existing.usage;
    final extraInfo = patch.containsKey('extra_info')
        ? patch['extra_info'] as String?
        : existing.extraInfo;
    await db.execute(
      Sql.named('''
        UPDATE products SET
          name = @name, kind = @kind, description = @desc,
          price_rub = @price, accent_color = @ac,
          ingredients = @ing::jsonb, tags = @tags::jsonb,
          skin_types = @st::jsonb,
          gentle = @g, routine_phase = @rp,
          buy_url = @buy_url,
          composition = @comp,
          precautions = @prec,
          usage_instructions = @use,
          extra_info = @extra,
          status = 'draft',
          moderation_status = 'pending',
          moderation_reason = NULL,
          submitted_at = now(),
          reviewed_at = NULL,
          reviewed_by = NULL
        WHERE id = @id
      '''),
      parameters: {
        'id': productId,
        'name': patched.name,
        'kind': patched.kind,
        'desc': patched.description,
        'price': patched.priceRub,
        'ac': patched.accentColor,
        'ing': jsonEncode(patched.ingredients),
        'tags': jsonEncode(patched.tags),
        'st': jsonEncode(patched.skinTypes),
        'g': patched.gentle,
        'rp': patched.routinePhase,
        'buy_url': patched.buyUrl,
        'comp': composition,
        'prec': precautions,
        'use': usage,
        'extra': extraInfo,
      },
    );
  }

  /// Admin moderation verdict. Approved → also flip status to published
  /// so the catalog picks it up immediately. Rejected keeps it hidden and
  /// stores the reason for the partner to read.
  Future<void> moderate({
    required String productId,
    required String moderationStatus, // 'approved' | 'rejected'
    String? reason,
    required String reviewerAdminId,
  }) async {
    final makeLive = moderationStatus == 'approved';
    await db.execute(
      Sql.named('''
        UPDATE products SET
          moderation_status = @ms,
          moderation_reason = @reason,
          reviewed_at = now(),
          reviewed_by = @admin,
          status = CASE WHEN @live THEN 'published' ELSE status END
        WHERE id = @id
      '''),
      parameters: {
        'id': productId,
        'ms': moderationStatus,
        'reason': reason,
        'admin': reviewerAdminId,
        'live': makeLive,
      },
    );
  }

  /// Verify a product belongs to one of [partnerId]'s brands. Used by
  /// partner endpoints before edits/deletes.
  Future<bool> isOwnedByPartner(String productId, String partnerId) async {
    final r = await db.execute(
      Sql.named('''
        SELECT 1 FROM products p JOIN brands b ON b.id = p.brand_id
        WHERE p.id = @id AND b.owner_partner_id = @partner
      '''),
      parameters: {'id': productId, 'partner': partnerId},
    );
    return r.isNotEmpty;
  }

  /// Flip a product back to the moderation queue. Used when a partner
  /// changes a photo on a previously-approved product — the picture is
  /// part of the listing, so it has to be re-reviewed.
  Future<void> resubmitForModeration(String productId) async {
    await db.execute(
      Sql.named('''
        UPDATE products SET
          status = 'draft',
          moderation_status = 'pending',
          moderation_reason = NULL,
          submitted_at = now(),
          reviewed_at = NULL,
          reviewed_by = NULL
        WHERE id = @id
      '''),
      parameters: {'id': productId},
    );
  }

  Future<void> deleteByPartner(String productId) async {
    // Allowed only when not yet approved — repo-layer guard, handler also
    // double-checks before invoking.
    await db.execute(
      Sql.named('''
        DELETE FROM products
        WHERE id = @id AND moderation_status IN ('pending', 'rejected')
      '''),
      parameters: {'id': productId},
    );
  }

  Future<ProductRow?> findBySlug(String slug, {bool publishedOnly = false}) async {
    final extra = publishedOnly ? " AND status = 'published'" : '';
    final r = await db.execute(
      Sql.named('SELECT $_cols FROM products WHERE slug = @s$extra'),
      parameters: {'s': slug},
    );
    return r.isEmpty ? null : ProductRow.fromRow(r.first);
  }

  Future<ProductRow?> findById(String id) async {
    final r = await db.execute(
      Sql.named('SELECT $_cols FROM products WHERE id = @id'),
      parameters: {'id': id},
    );
    return r.isEmpty ? null : ProductRow.fromRow(r.first);
  }

  /// Partner id that currently owns the brand of this product, or null if
  /// the brand has no owner (legacy admin-managed). Used by partner stats
  /// endpoints to authorise drill-down access.
  Future<String?> ownerPartnerId(String productId) async {
    final r = await db.execute(
      Sql.named('''
        SELECT b.owner_partner_id
        FROM products p JOIN brands b ON b.id = p.brand_id
        WHERE p.id = @id
      '''),
      parameters: {'id': productId},
    );
    return r.isEmpty ? null : r.first[0] as String?;
  }

  Future<({List<int> bytes, String mime})?> getPhoto(String id,
      {int slot = 1}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT bytes, mime FROM product_photos
        WHERE product_id = @id AND slot = @s
      '''),
      parameters: {'id': id, 's': slot},
    );
    if (r.isNotEmpty && r.first[0] != null) {
      return (
        bytes: r.first[0] as List<int>,
        mime: (r.first[1] as String?) ?? 'image/jpeg',
      );
    }
    // Back-compat: fall back to the legacy products.photo blob if the new
    // table doesn't have slot 1 yet (migration mid-rollout / older row).
    if (slot == 1) {
      final r2 = await db.execute(
        Sql.named('SELECT photo, photo_mime FROM products WHERE id = @id'),
        parameters: {'id': id},
      );
      if (r2.isEmpty || r2.first[0] == null) return null;
      return (
        bytes: r2.first[0] as List<int>,
        mime: (r2.first[1] as String?) ?? 'image/jpeg',
      );
    }
    return null;
  }

  Future<void> setPhoto({
    required String id,
    required List<int> bytes,
    required String mime,
    int slot = 1,
  }) async {
    final b = TypedValue(Type.byteArray, Uint8List.fromList(bytes));
    await db.execute(
      Sql.named('''
        INSERT INTO product_photos (product_id, slot, bytes, mime)
        VALUES (@id, @s, @b, @m)
        ON CONFLICT (product_id, slot) DO UPDATE SET
          bytes = EXCLUDED.bytes,
          mime = EXCLUDED.mime,
          uploaded_at = now()
      '''),
      parameters: {'id': id, 's': slot, 'b': b, 'm': mime},
    );
    // Mirror slot 1 into the legacy column for one release so older code
    // that still reads products.photo doesn't see an empty image.
    if (slot == 1) {
      await db.execute(
        Sql.named(
            'UPDATE products SET photo = @b, photo_mime = @m WHERE id = @id'),
        parameters: {'id': id, 'b': b, 'm': mime},
      );
    }
  }

  Future<void> removePhoto({required String id, required int slot}) async {
    await db.execute(
      Sql.named('''
        DELETE FROM product_photos
        WHERE product_id = @id AND slot = @s
      '''),
      parameters: {'id': id, 's': slot},
    );
    if (slot == 1) {
      await db.execute(
        Sql.named('UPDATE products SET photo = NULL, photo_mime = NULL '
            'WHERE id = @id'),
        parameters: {'id': id},
      );
    }
  }

  Future<List<int>> photoSlots(String id) async {
    final r = await db.execute(
      Sql.named('''
        SELECT slot FROM product_photos
        WHERE product_id = @id ORDER BY slot
      '''),
      parameters: {'id': id},
    );
    final slots = r.map((row) => (row[0] as int)).toList();
    if (slots.isEmpty) {
      // Legacy single-photo case.
      final r2 = await db.execute(
        Sql.named(
            'SELECT 1 FROM products WHERE id = @id AND photo IS NOT NULL'),
        parameters: {'id': id},
      );
      if (r2.isNotEmpty) return [1];
    }
    return slots;
  }

  Future<void> delete(String id) async {
    await db.execute(
      Sql.named('DELETE FROM products WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  /// Patch only the fields that are present in [patch]. Returns the new row.
  Future<ProductRow?> update(String id, Map<String, dynamic> patch) async {
    final existing = await findById(id);
    if (existing == null) return null;
    final updated = ProductRow(
      id: existing.id,
      slug: existing.slug,
      brand: (patch['brand'] as String?) ?? existing.brand,
      name: (patch['name'] as String?) ?? existing.name,
      kind: (patch['kind'] as String?) ?? existing.kind,
      description:
          (patch['description'] as String?) ?? existing.description,
      priceRub:
          (patch['price_rub'] as num?)?.toInt() ?? existing.priceRub,
      accentColor:
          (patch['accent_color'] as String?) ?? existing.accentColor,
      ingredients: (patch['ingredients'] as List?)?.cast<String>() ??
          existing.ingredients,
      tags:
          (patch['tags'] as List?)?.cast<String>() ?? existing.tags,
      skinTypes: (patch['skin_types'] as List?)?.cast<String>() ??
          existing.skinTypes,
      isActive:
          (patch['is_active'] as bool?) ?? existing.isActive,
      gentle: (patch['gentle'] as bool?) ?? existing.gentle,
      routinePhase:
          (patch['routine_phase'] as String?) ?? existing.routinePhase,
      status: (patch['status'] as String?) ?? existing.status,
      hasPhoto: existing.hasPhoto,
      // patch.containsKey lets admin clear the buy URL by sending null
      // explicitly; otherwise we keep what was there before.
      buyUrl: patch.containsKey('buy_url')
          ? patch['buy_url'] as String?
          : existing.buyUrl,
    );
    final composition = patch.containsKey('composition')
        ? patch['composition'] as String?
        : existing.composition;
    final precautions = patch.containsKey('precautions')
        ? patch['precautions'] as String?
        : existing.precautions;
    final usage =
        patch.containsKey('usage') ? patch['usage'] as String? : existing.usage;
    final extraInfo = patch.containsKey('extra_info')
        ? patch['extra_info'] as String?
        : existing.extraInfo;
    await db.execute(
      Sql.named('''
        UPDATE products SET
          brand = @brand, name = @name, kind = @kind, description = @desc,
          price_rub = @price, accent_color = @ac,
          ingredients = @ing::jsonb, tags = @tags::jsonb,
          skin_types = @st::jsonb,
          is_active_ingredient = @ai, gentle = @g, routine_phase = @rp,
          status = @status, buy_url = @buy_url,
          composition = @comp, precautions = @prec,
          usage_instructions = @use, extra_info = @extra
        WHERE id = @id
      '''),
      parameters: {
        'id': updated.id,
        'brand': updated.brand,
        'name': updated.name,
        'kind': updated.kind,
        'desc': updated.description,
        'price': updated.priceRub,
        'ac': updated.accentColor,
        'ing': jsonEncode(updated.ingredients),
        'tags': jsonEncode(updated.tags),
        'st': jsonEncode(updated.skinTypes),
        'ai': updated.isActive,
        'g': updated.gentle,
        'rp': updated.routinePhase,
        'status': updated.status,
        'buy_url': updated.buyUrl,
        'comp': composition,
        'prec': precautions,
        'use': usage,
        'extra': extraInfo,
      },
    );
    return updated;
  }

  Future<void> upsert(ProductRow p) async {
    // products.brand_id has been NOT NULL since migration 017_partners.
    // Resolve (or auto-create) the brand row matching p.brand before the
    // insert so admin-flow creates don't violate the FK. Brand creation
    // here is idempotent — CITEXT-unique name handles concurrent races.
    final brandId = await _resolveBrandId(p.brand);
    await db.execute(
      Sql.named('''
        INSERT INTO products (
          id, slug, brand, name, kind, description, price_rub, accent_color,
          ingredients, tags, skin_types, is_active_ingredient, gentle,
          routine_phase, status, buy_url, composition, precautions,
          usage_instructions, extra_info, brand_id
        ) VALUES (
          @id, @slug, @brand, @name, @kind, @desc, @price, @ac,
          @ing::jsonb, @tags::jsonb, @st::jsonb, @ai, @g, @rp, @status,
          @buy_url, @comp, @prec, @use, @extra, @brand_id
        )
        ON CONFLICT (slug) DO UPDATE SET
          brand = EXCLUDED.brand, name = EXCLUDED.name, kind = EXCLUDED.kind,
          description = EXCLUDED.description, price_rub = EXCLUDED.price_rub,
          accent_color = EXCLUDED.accent_color, ingredients = EXCLUDED.ingredients,
          tags = EXCLUDED.tags, skin_types = EXCLUDED.skin_types,
          is_active_ingredient = EXCLUDED.is_active_ingredient,
          gentle = EXCLUDED.gentle, routine_phase = EXCLUDED.routine_phase,
          status = EXCLUDED.status, buy_url = EXCLUDED.buy_url,
          composition = EXCLUDED.composition,
          precautions = EXCLUDED.precautions,
          usage_instructions = EXCLUDED.usage_instructions,
          extra_info = EXCLUDED.extra_info,
          brand_id = EXCLUDED.brand_id
      '''),
      parameters: {
        'id': p.id,
        'slug': p.slug,
        'brand': p.brand,
        'name': p.name,
        'kind': p.kind,
        'desc': p.description,
        'price': p.priceRub,
        'ac': p.accentColor,
        'ing': jsonEncode(p.ingredients),
        'tags': jsonEncode(p.tags),
        'st': jsonEncode(p.skinTypes),
        'ai': p.isActive,
        'g': p.gentle,
        'rp': p.routinePhase,
        'status': p.status,
        'buy_url': p.buyUrl,
        'comp': p.composition,
        'prec': p.precautions,
        'use': p.usage,
        'extra': p.extraInfo,
        'brand_id': brandId,
      },
    );
  }

  /// Looks up `brands.id` by case-insensitive name (CITEXT column). If the
  /// brand doesn't exist yet, creates it as `approved` so admin-created
  /// products go live immediately. Returns the brand's UUID.
  Future<String> _resolveBrandId(String brandName) async {
    final found = await db.execute(
      Sql.named('SELECT id FROM brands WHERE name = @n LIMIT 1'),
      parameters: {'n': brandName},
    );
    if (found.isNotEmpty) return found.first[0] as String;
    final id = _uuid.v4();
    final slug = brandName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    try {
      await db.execute(
        Sql.named('''
          INSERT INTO brands (id, name, slug, status)
          VALUES (@id, @n, @s, 'approved')
        '''),
        parameters: {'id': id, 'n': brandName, 's': slug.isEmpty ? id : slug},
      );
      return id;
    } on ServerException catch (e) {
      if (e.code != '23505') rethrow;
      // Race lost — another writer just created the same brand. Re-fetch.
      final r = await db.execute(
        Sql.named('SELECT id FROM brands WHERE name = @n LIMIT 1'),
        parameters: {'n': brandName},
      );
      return r.first[0] as String;
    }
  }
}

class ShelfItem {
  ShelfItem({
    required this.product,
    required this.status,
    required this.addedAt,
    this.notes,
    this.fillLevel,
    this.openedAt,
    this.expiresAt,
    this.paoMonths,
  });
  final ProductRow product;
  final String status;
  final DateTime addedAt;
  final String? notes;
  final String? fillLevel;
  final DateTime? openedAt;
  final DateTime? expiresAt;
  final int? paoMonths;
}

class CustomShelfItem {
  CustomShelfItem({
    required this.id,
    required this.userId,
    required this.brand,
    required this.name,
    required this.kind,
    required this.accentColor,
    required this.hasPhoto,
    required this.ingredients,
    required this.status,
    required this.addedAt,
    this.fillLevel,
    this.openedAt,
    this.expiresAt,
    this.paoMonths,
    this.notes,
  });
  final String id;
  final String userId;
  final String brand;
  final String name;
  final String kind;
  final String accentColor;
  final bool hasPhoto;
  final List<String> ingredients;
  final String status;
  final DateTime addedAt;
  final String? fillLevel;
  final DateTime? openedAt;
  final DateTime? expiresAt;
  final int? paoMonths;
  final String? notes;
}

class UserProductRepository {
  UserProductRepository(this.db);
  final Pool db;

  Future<List<ShelfItem>> list(String userId) async {
    // Select the same 24 product columns ProductRow.fromRow expects (kept
    // in sync with ProductRepository._cols), then append user_products
    // fields after. Earlier we shipped only 14 columns which silently set
    // hasPhoto=false on every shelf item.
    final r = await db.execute(
      Sql.named('''
        SELECT p.id, p.slug, p.brand, p.name, p.kind, p.description,
               p.price_rub, p.accent_color, p.ingredients, p.tags,
               p.skin_types, p.is_active_ingredient, p.gentle, p.routine_phase,
               p.status, (p.photo IS NOT NULL), p.buy_url,
               p.moderation_status, p.moderation_reason,
               p.submitted_by_partner_id, p.composition, p.precautions,
               p.usage_instructions, p.extra_info,
               up.status AS up_status, up.added_at, up.notes,
               up.fill_level, up.opened_at, up.expires_at, up.pao_months
        FROM user_products up
        JOIN products p ON p.id = up.product_id
        WHERE up.user_id = @u
        ORDER BY up.added_at DESC
      '''),
      parameters: {'u': userId},
    );
    return r.map((row) {
      return ShelfItem(
        product: ProductRow.fromRow(row.sublist(0, 24)),
        status: row[24] as String,
        addedAt: row[25] as DateTime,
        notes: row[26] as String?,
        fillLevel: row[27] as String?,
        openedAt: row[28] as DateTime?,
        expiresAt: row[29] as DateTime?,
        paoMonths: row[30] as int?,
      );
    }).toList();
  }

  /// Patch the shelf item's expiry / fill_level fields. Only non-null keys
  /// in [patch] are written; keys explicitly set to null in [clear] are
  /// nulled out (caller passes them to remove a date).
  Future<void> patch({
    required String userId,
    required String productId,
    String? fillLevel,
    DateTime? openedAt,
    DateTime? expiresAt,
    int? paoMonths,
    Set<String> clear = const {},
  }) async {
    final sets = <String>[];
    final params = <String, dynamic>{'u': userId, 'p': productId};
    if (fillLevel != null) {
      sets.add('fill_level = @fl');
      params['fl'] = fillLevel;
    } else if (clear.contains('fill_level')) {
      sets.add('fill_level = NULL');
    }
    if (openedAt != null) {
      sets.add('opened_at = @oa');
      params['oa'] = openedAt;
    } else if (clear.contains('opened_at')) {
      sets.add('opened_at = NULL');
    }
    if (expiresAt != null) {
      sets.add('expires_at = @ea');
      params['ea'] = expiresAt;
    } else if (clear.contains('expires_at')) {
      sets.add('expires_at = NULL');
    }
    if (paoMonths != null) {
      sets.add('pao_months = @pm');
      params['pm'] = paoMonths;
    } else if (clear.contains('pao_months')) {
      sets.add('pao_months = NULL');
    }
    if (sets.isEmpty) return;
    await db.execute(
      Sql.named('''
        UPDATE user_products SET ${sets.join(', ')}
        WHERE user_id = @u AND product_id = @p
      '''),
      parameters: params,
    );
  }

  Future<void> upsert({
    required String userId,
    required String productId,
    required String status,
    String? notes,
  }) async {
    await db.execute(
      Sql.named('''
        INSERT INTO user_products (user_id, product_id, status, notes)
        VALUES (@u, @p, @s, @n)
        ON CONFLICT (user_id, product_id) DO UPDATE
          SET status = EXCLUDED.status, notes = EXCLUDED.notes
      '''),
      parameters: {'u': userId, 'p': productId, 's': status, 'n': notes},
    );
  }

  Future<void> remove(
      {required String userId, required String productId}) async {
    await db.execute(
      Sql.named(
          'DELETE FROM user_products WHERE user_id = @u AND product_id = @p'),
      parameters: {'u': userId, 'p': productId},
    );
  }
}

class UserCustomProductRepository {
  UserCustomProductRepository(this.db);
  final Pool db;

  static const _cols =
      'id, user_id, brand, name, kind, accent_color, (photo IS NOT NULL), '
      'ingredients, status, fill_level, opened_at, expires_at, pao_months, '
      'notes, added_at';

  CustomShelfItem _fromRow(List<dynamic> r) => CustomShelfItem(
        id: r[0] as String,
        userId: r[1] as String,
        brand: r[2] as String,
        name: r[3] as String,
        kind: r[4] as String,
        accentColor: r[5] as String,
        hasPhoto: r[6] as bool,
        ingredients:
            (r[7] as List? ?? const []).map((e) => '$e').toList(),
        status: r[8] as String,
        fillLevel: r[9] as String?,
        openedAt: r[10] as DateTime?,
        expiresAt: r[11] as DateTime?,
        paoMonths: r[12] as int?,
        notes: r[13] as String?,
        addedAt: r[14] as DateTime,
      );

  Future<List<CustomShelfItem>> list(String userId) async {
    final r = await db.execute(
      Sql.named(
          'SELECT $_cols FROM user_custom_products WHERE user_id = @u ORDER BY added_at DESC'),
      parameters: {'u': userId},
    );
    return r.map(_fromRow).toList();
  }

  Future<CustomShelfItem?> findById(
      {required String userId, required String id}) async {
    final r = await db.execute(
      Sql.named(
          'SELECT $_cols FROM user_custom_products WHERE id = @i AND user_id = @u'),
      parameters: {'i': id, 'u': userId},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first);
  }

  Future<CustomShelfItem> create({
    required String userId,
    required String brand,
    required String name,
    required String kind,
    String accentColor = '#D98FA3',
    List<String> ingredients = const [],
    String status = 'have',
    String? fillLevel,
    DateTime? openedAt,
    DateTime? expiresAt,
    int? paoMonths,
    String? notes,
  }) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO user_custom_products (
          id, user_id, brand, name, kind, accent_color, ingredients,
          status, fill_level, opened_at, expires_at, pao_months, notes
        ) VALUES (
          @id, @u, @b, @n, @k, @ac, @ing::jsonb,
          @s, @fl, @oa, @ea, @pm, @no
        )
      '''),
      parameters: {
        'id': id,
        'u': userId,
        'b': brand,
        'n': name,
        'k': kind,
        'ac': accentColor,
        'ing': jsonEncode(ingredients),
        's': status,
        'fl': fillLevel,
        'oa': openedAt,
        'ea': expiresAt,
        'pm': paoMonths,
        'no': notes,
      },
    );
    return (await findById(userId: userId, id: id))!;
  }

  Future<void> patch({
    required String userId,
    required String id,
    String? brand,
    String? name,
    String? kind,
    String? status,
    String? fillLevel,
    DateTime? openedAt,
    DateTime? expiresAt,
    int? paoMonths,
    String? notes,
    Set<String> clear = const {},
  }) async {
    final sets = <String>[];
    final params = <String, dynamic>{'u': userId, 'i': id};
    void str(String key, String col, String? v) {
      if (v != null) {
        sets.add('$col = @$key');
        params[key] = v;
      } else if (clear.contains(col)) {
        sets.add('$col = NULL');
      }
    }

    str('b', 'brand', brand);
    str('n', 'name', name);
    str('k', 'kind', kind);
    str('s', 'status', status);
    str('fl', 'fill_level', fillLevel);
    str('no', 'notes', notes);
    if (openedAt != null) {
      sets.add('opened_at = @oa');
      params['oa'] = openedAt;
    } else if (clear.contains('opened_at')) {
      sets.add('opened_at = NULL');
    }
    if (expiresAt != null) {
      sets.add('expires_at = @ea');
      params['ea'] = expiresAt;
    } else if (clear.contains('expires_at')) {
      sets.add('expires_at = NULL');
    }
    if (paoMonths != null) {
      sets.add('pao_months = @pm');
      params['pm'] = paoMonths;
    } else if (clear.contains('pao_months')) {
      sets.add('pao_months = NULL');
    }
    if (sets.isEmpty) return;
    await db.execute(
      Sql.named(
          'UPDATE user_custom_products SET ${sets.join(', ')} WHERE id = @i AND user_id = @u'),
      parameters: params,
    );
  }

  Future<void> remove({required String userId, required String id}) async {
    await db.execute(
      Sql.named(
          'DELETE FROM user_custom_products WHERE id = @i AND user_id = @u'),
      parameters: {'i': id, 'u': userId},
    );
  }

  Future<({Uint8List bytes, String mime})?> getPhoto({
    required String userId,
    required String id,
  }) async {
    final r = await db.execute(
      Sql.named(
          'SELECT photo, COALESCE(photo_mime, \'image/jpeg\') FROM user_custom_products WHERE id = @i AND user_id = @u'),
      parameters: {'i': id, 'u': userId},
    );
    if (r.isEmpty) return null;
    final bytes = r.first[0];
    if (bytes == null) return null;
    return (
      bytes: Uint8List.fromList(bytes as List<int>),
      mime: r.first[1] as String,
    );
  }

  Future<bool> setPhoto({
    required String userId,
    required String id,
    required List<int> bytes,
    required String mime,
  }) async {
    final b = TypedValue(Type.byteArray, Uint8List.fromList(bytes));
    final r = await db.execute(
      Sql.named('''
        UPDATE user_custom_products SET photo = @b, photo_mime = @m
        WHERE id = @i AND user_id = @u
      '''),
      parameters: {'i': id, 'u': userId, 'b': b, 'm': mime},
    );
    return r.affectedRows > 0;
  }
}

class UserFavoriteRepository {
  UserFavoriteRepository(this.db);
  final Pool db;

  Future<void> add(
      {required String userId, required String productId}) async {
    await db.execute(
      Sql.named('''
        INSERT INTO user_favorites (user_id, product_id)
        VALUES (@u, @p)
        ON CONFLICT (user_id, product_id) DO NOTHING
      '''),
      parameters: {'u': userId, 'p': productId},
    );
  }

  Future<void> remove(
      {required String userId, required String productId}) async {
    await db.execute(
      Sql.named(
          'DELETE FROM user_favorites WHERE user_id = @u AND product_id = @p'),
      parameters: {'u': userId, 'p': productId},
    );
  }

  Future<bool> contains(
      {required String userId, required String productId}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT 1 FROM user_favorites
        WHERE user_id = @u AND product_id = @p
        LIMIT 1
      '''),
      parameters: {'u': userId, 'p': productId},
    );
    return r.isNotEmpty;
  }

  Future<List<String>> listIds(String userId) async {
    final r = await db.execute(
      Sql.named('''
        SELECT product_id FROM user_favorites
        WHERE user_id = @u ORDER BY added_at DESC
      '''),
      parameters: {'u': userId},
    );
    return r.map((row) => row[0] as String).toList();
  }
}

class ScanRow {
  ScanRow({
    required this.id,
    required this.userId,
    required this.score,
    required this.hydration,
    required this.sebum,
    required this.tone,
    required this.pores,
    required this.zones,
    required this.insight,
    required this.createdAt,
    this.hasPhoto = true,
    this.faceGeom,
    this.concerns = const [],
  });

  final String id;
  final String userId;
  final int score;
  final int hydration;
  final int sebum;
  final int tone;
  final int pores;
  final Map<String, int> zones;
  final String insight;
  final DateTime createdAt;
  final bool hasPhoto;
  final Map<String, dynamic>? faceGeom;
  /// Concern tags from GigaChat Vision (acne, pih, redness, dehydration,
  /// dullness, aging, sensitivity, oiliness, dryness). Empty on legacy
  /// scans created before migration 022.
  final List<String> concerns;

  Map<String, dynamic> toJson() => {
        'id': id,
        'score': score,
        'hydration': hydration,
        'sebum': sebum,
        'tone': tone,
        'pores': pores,
        'zones': zones,
        'insight': insight,
        'has_photo': hasPhoto,
        'created_at': createdAt.toUtc().toIso8601String(),
        'concerns': concerns,
        if (faceGeom != null) 'face': faceGeom,
      };
}

class ScanRepository {
  ScanRepository(this.db);
  final Pool db;

  Future<ScanRow> create({
    required String userId,
    required List<int>? photo,
    required String? mime,
    required int score,
    required int hydration,
    required int sebum,
    required int tone,
    required int pores,
    required Map<String, int> zones,
    required String insight,
    Map<String, dynamic>? faceGeom,
    List<String> concerns = const [],
  }) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO scans (id, user_id, photo, photo_mime, score, hydration,
                           sebum, tone, pores, zones, insight, face_geom,
                           concerns)
        VALUES (@id, @u, @p, @m, @sc, @h, @se, @t, @po, @z::jsonb, @i,
                @fg::jsonb, @cn::jsonb)
      '''),
      parameters: {
        'id': id,
        'u': userId,
        'p': photo == null
            ? null
            : TypedValue(Type.byteArray, Uint8List.fromList(photo)),
        'm': mime,
        'sc': score,
        'h': hydration,
        'se': sebum,
        't': tone,
        'po': pores,
        'z': jsonEncode(zones),
        'i': insight,
        'fg': faceGeom == null ? null : jsonEncode(faceGeom),
        'cn': jsonEncode(concerns),
      },
    );
    return ScanRow(
      id: id,
      userId: userId,
      score: score,
      hydration: hydration,
      sebum: sebum,
      tone: tone,
      pores: pores,
      zones: zones,
      insight: insight,
      createdAt: DateTime.now().toUtc(),
      hasPhoto: photo != null,
      faceGeom: faceGeom,
      concerns: List.unmodifiable(concerns),
    );
  }

  Future<ScanRow?> findById(
      {required String userId, required String id}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, user_id, score, hydration, sebum, tone, pores, zones,
               insight, created_at, photo IS NOT NULL, face_geom, concerns
        FROM scans WHERE id = @id AND user_id = @u
      '''),
      parameters: {'id': id, 'u': userId},
    );
    if (r.isEmpty) return null;
    final row = r.first;
    return ScanRow(
      id: row[0] as String,
      userId: row[1] as String,
      score: row[2] as int,
      hydration: row[3] as int,
      sebum: row[4] as int,
      tone: row[5] as int,
      pores: row[6] as int,
      zones: ((row[7] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', (v as num).toInt())),
      insight: row[8] as String? ?? '',
      createdAt: row[9] as DateTime,
      hasPhoto: row[10] as bool,
      faceGeom: (row[11] as Map?)?.cast<String, dynamic>(),
      concerns: ((row[12] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }

  Future<({List<int> bytes, String mime})?> getPhoto(
      {required String userId, required String id}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT photo, photo_mime FROM scans
        WHERE id = @id AND user_id = @u
      '''),
      parameters: {'id': id, 'u': userId},
    );
    if (r.isEmpty || r.first[0] == null) return null;
    return (
      bytes: r.first[0] as List<int>,
      mime: (r.first[1] as String?) ?? 'image/jpeg',
    );
  }

  Future<List<ScanRow>> listForUser(String userId, {int limit = 50}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, user_id, score, hydration, sebum, tone, pores, zones,
               insight, created_at, photo IS NOT NULL, face_geom, concerns
        FROM scans WHERE user_id = @u
        ORDER BY created_at DESC LIMIT @lim
      '''),
      parameters: {'u': userId, 'lim': limit},
    );
    return r
        .map((row) => ScanRow(
              id: row[0] as String,
              userId: row[1] as String,
              score: row[2] as int,
              hydration: row[3] as int,
              sebum: row[4] as int,
              tone: row[5] as int,
              pores: row[6] as int,
              zones: ((row[7] as Map?) ?? const {})
                  .map((k, v) => MapEntry('$k', (v as num).toInt())),
              insight: row[8] as String? ?? '',
              createdAt: row[9] as DateTime,
              hasPhoto: row[10] as bool,
              faceGeom: (row[11] as Map?)?.cast<String, dynamic>(),
              concerns:
                  ((row[12] as List?) ?? const []).map((e) => '$e').toList(),
            ))
        .toList();
  }
}

/// Real image-based skin analysis.
/// Decodes the photo, samples skin-toned pixels per face region, and computes
/// metrics from actual visual content. Profile only nudges the insight string.
class ScanAnalysis {
  ScanAnalysis({
    required this.score,
    required this.hydration,
    required this.sebum,
    required this.tone,
    required this.pores,
    required this.zones,
    required this.insight,
    required this.qualityWarnings,
    required this.meta,
    this.faceGeom,
  });

  final int score;
  final int hydration;
  final int sebum;
  final int tone;
  final int pores;
  final Map<String, int> zones;
  final String insight;
  final List<String> qualityWarnings;
  final Map<String, dynamic> meta;
  /// Normalised face bounding box on the source photo:
  /// `{"bbox": [x0, y0, x1, y1]}` with values in [0..1]. Null when no
  /// face could be located (e.g. fallback path with no photo).
  final Map<String, dynamic>? faceGeom;
}

/// Heuristic skin-tone detection in RGB (Kovac et al., simplified).
bool _isSkinPixel(int r, int g, int b) {
  if (r < 95 || g < 40 || b < 20) return false;
  if (r <= g || r <= b) return false;
  if ((r - g).abs() < 15) return false;
  return true;
}

ScanAnalysis analyzeScan({
  required List<int> photoBytes,
  required Map<String, dynamic> profile,
}) {
  final t0 = DateTime.now();
  final warnings = <String>[];

  // Empty bytes (e.g. derm-2 retake without photo). Fall back to safe defaults.
  if (photoBytes.length < 200) {
    return _profileFallback(profile, warnings: ['no_photo']);
  }

  img.Image? decoded;
  try {
    decoded = img.decodeImage(Uint8List.fromList(photoBytes));
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return _profileFallback(profile, warnings: ['cannot_decode']);
  }

  // Downscale for speed (analysis is rough — 256-512px is plenty).
  final image = decoded.width > 512
      ? img.copyResize(decoded, width: 512)
      : decoded;
  final w = image.width, h = image.height;
  if (w < 128 || h < 128) {
    return _profileFallback(profile,
        warnings: ['image_too_small'],
        meta: {'image_size': '${w}x$h'});
  }

  // Single pass: collect per-region stats over skin-detected pixels.
  final regions = <String, _RegionAcc>{
    'forehead': _RegionAcc(),
    'tzone': _RegionAcc(),
    'cheeks_l': _RegionAcc(),
    'cheeks_r': _RegionAcc(),
    'chin': _RegionAcc(),
    'all': _RegionAcc(),
  };

  final yForehead = (h * 0.18).round();
  final yEyes = (h * 0.42).round();
  final yMouth = (h * 0.66).round();
  final yChinTop = (h * 0.78).round();
  final xCenter = w / 2;
  final tzoneHalfW = w * 0.12;

  // Face bbox in pixel coords. Grows to include each detected skin pixel.
  var faceMinX = w, faceMaxX = 0, faceMinY = h, faceMaxY = 0;

  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      final px = image.getPixel(x, y);
      final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
      if (!_isSkinPixel(r, g, b)) continue;

      if (x < faceMinX) faceMinX = x;
      if (x > faceMaxX) faceMaxX = x;
      if (y < faceMinY) faceMinY = y;
      if (y > faceMaxY) faceMaxY = y;

      final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
      final all = regions['all']!;
      all.add(r, g, b, lum);

      // Region assignment by y/x.
      if (y < yForehead) {
        regions['forehead']!.add(r, g, b, lum);
        if ((x - xCenter).abs() < tzoneHalfW) {
          regions['tzone']!.add(r, g, b, lum);
        }
      } else if (y < yMouth) {
        if ((x - xCenter).abs() < tzoneHalfW) {
          regions['tzone']!.add(r, g, b, lum);
        } else if (y > yEyes) {
          if (x < xCenter) {
            regions['cheeks_l']!.add(r, g, b, lum);
          } else {
            regions['cheeks_r']!.add(r, g, b, lum);
          }
        }
      } else if (y >= yChinTop) {
        regions['chin']!.add(r, g, b, lum);
      }
    }
  }

  final all = regions['all']!;
  final skinPct = all.count / ((w * h) / 4); // we sampled every 2nd pixel both axes
  final meta = <String, dynamic>{
    'image_size': '${w}x$h',
    'skin_pct': (skinPct * 100).clamp(0, 100).toStringAsFixed(1),
  };

  // Threshold fraction-based, not absolute. Works for both small selfies and
  // larger frames. Need ≥3% skin-tone pixels OR at least 600 absolute samples.
  if (all.count < 600 && skinPct < 0.03) {
    return _profileFallback(profile,
        warnings: ['no_face_detected'], meta: meta);
  }

  final avgLum = all.lumSum / all.count;
  if (avgLum < 0.18) warnings.add('image_too_dark');
  if (avgLum > 0.92) warnings.add('image_overexposed');

  // ===== Metrics =====

  // Hydration ≈ smoothness (low variance in skin tone = uniform/healthy).
  // varSkin is normalised so that variance 0 → 95, high variance → 50.
  final varSkin = all.lumVariance();
  final hydration = (95 - (varSkin * 1400).clamp(0, 45)).round().clamp(0, 100);

  // Sebum ≈ specular highlight density in T-zone (very bright pixels).
  final tzone = regions['tzone']!;
  final tzoneShine = tzone.brightFraction(0.82);
  final sebum = (35 + tzoneShine * 90).round().clamp(0, 100);

  // Tone ≈ inverse of color variance (chromatic). Yellower/redder patches
  // bring this down.
  final chromaVar = all.chromaVariance();
  final tone = (95 - (chromaVar * 900).clamp(0, 45)).round().clamp(0, 100);

  // Pores ≈ horizontal-edge density inverse: smoother face → fewer edges → high score.
  // Approximate by luminance std-dev penalty.
  final pores = (90 - (varSkin * 1100).clamp(0, 50)).round().clamp(0, 100);

  // Zones: per-region "health" — uniform skin tone, not too red, not too oily.
  int zoneScore(_RegionAcc r, {double oilThreshold = 0.78, double oilPenalty = 30}) {
    if (r.count < 80) return 70;
    final v = r.lumVariance();
    final shine = r.brightFraction(oilThreshold);
    final redness = r.rednessIndex();
    return (90 -
            (v * 1200).clamp(0, 30) -
            (shine * oilPenalty).clamp(0, oilPenalty) -
            (redness * 70).clamp(0, 30))
        .round()
        .clamp(0, 100);
  }

  final fhScore = zoneScore(regions['forehead']!);
  final tzScore =
      zoneScore(regions['tzone']!, oilThreshold: 0.82, oilPenalty: 35);
  final chL = zoneScore(regions['cheeks_l']!, oilThreshold: 0.85);
  final chR = zoneScore(regions['cheeks_r']!, oilThreshold: 0.85);
  final cheeksAvg = ((chL + chR) / 2).round();
  final chinScore = zoneScore(regions['chin']!);

  final score =
      ((hydration + (100 - (sebum - 50).abs() * 2).clamp(0, 100) + tone + pores) /
              4)
          .round()
          .clamp(0, 100);

  // Insight selection from metric profile (not random).
  String insight;
  if (sebum > 65 && tzScore < 70) {
    insight =
        'Т-зона активничает. Деликатная очистка + ниацинамид вечером выровнят блеск.';
  } else if (avgLum < 0.3) {
    insight = 'Свет тусклый — повтори в дневное окно для точности. Базово кожа держится.';
  } else if (hydration < 60) {
    insight =
        'Заметна обезвоженность. Эссенция и крем с гиалуронкой помогут к завтрашнему дню.';
  } else if (cheeksAvg < 65) {
    insight =
        'Щёки чуть раздражены — пара дней мягкого ухода без активов восстановит.';
  } else if (score >= 80) {
    insight = 'Кожа в форме. Не забудь SPF утром — это твоя главная инвестиция.';
  } else {
    insight =
        'Тонко-ровно. Поддержим увлажнение и аккуратно введём активы по схеме.';
  }

  meta['avg_lum'] = avgLum.toStringAsFixed(3);
  meta['processing_ms'] =
      DateTime.now().difference(t0).inMilliseconds;

  Map<String, dynamic>? faceGeom;
  if (faceMaxX > faceMinX && faceMaxY > faceMinY) {
    // Tighten the bbox slightly — skin detection picks up neck/edges and
    // the raw extents drift outside the actual face. 4 % inset works well
    // for selfie framing.
    final pad = 0.04;
    final x0 = (faceMinX / w).clamp(0.0, 1.0);
    final y0 = (faceMinY / h).clamp(0.0, 1.0);
    final x1 = (faceMaxX / w).clamp(0.0, 1.0);
    final y1 = (faceMaxY / h).clamp(0.0, 1.0);
    final bw = x1 - x0, bh = y1 - y0;
    faceGeom = {
      'bbox': [
        (x0 + bw * pad).clamp(0.0, 1.0),
        (y0 + bh * pad).clamp(0.0, 1.0),
        (x1 - bw * pad).clamp(0.0, 1.0),
        (y1 - bh * pad).clamp(0.0, 1.0),
      ],
    };
  }

  return ScanAnalysis(
    score: score,
    hydration: hydration,
    sebum: sebum,
    tone: tone,
    pores: pores,
    zones: {
      'forehead': fhScore,
      'tzone': tzScore,
      'cheeks': cheeksAvg,
      'chin': chinScore,
    },
    insight: insight,
    qualityWarnings: warnings,
    meta: meta,
    faceGeom: faceGeom,
  );
}

/// When the photo is unusable, fall back to profile-based defaults so the user
/// still sees a result. Marks `quality_warnings` so the client can flag.
ScanAnalysis _profileFallback(
  Map<String, dynamic> profile, {
  required List<String> warnings,
  Map<String, dynamic> meta = const {},
}) {
  final skinType = profile['skin_type'] as String?;
  final hydration = switch (skinType) {
    'dry' => 50,
    'oily' => 75,
    'combo' => 65,
    _ => 70,
  };
  final sebum = switch (skinType) {
    'oily' => 72,
    'combo' => 55,
    'dry' => 30,
    _ => 45,
  };
  return ScanAnalysis(
    score: 65,
    hydration: hydration,
    sebum: sebum,
    tone: 65,
    pores: 65,
    zones: const {
      'forehead': 65,
      'tzone': 65,
      'cheeks': 70,
      'chin': 65,
    },
    insight: 'Не получилось проанализировать фото. Попробуй переснять при дневном свете лицом к источнику.',
    qualityWarnings: warnings,
    meta: meta,
  );
}

class _RegionAcc {
  int count = 0;
  double rSum = 0, gSum = 0, bSum = 0, lumSum = 0, lumSqSum = 0;
  double chromaSqSum = 0;
  int brightCount82 = 0, brightCount85 = 0;

  void add(int r, int g, int b, double lum) {
    count++;
    rSum += r;
    gSum += g;
    bSum += b;
    lumSum += lum;
    lumSqSum += lum * lum;
    if (lum > 0.82) brightCount82++;
    if (lum > 0.85) brightCount85++;
    // chroma: distance from average grey for this pixel.
    final mean = (r + g + b) / 3.0;
    final c = ((r - mean).abs() + (g - mean).abs() + (b - mean).abs()) / 765.0;
    chromaSqSum += c * c;
  }

  double lumVariance() {
    if (count < 2) return 0;
    final mean = lumSum / count;
    final v = (lumSqSum / count) - mean * mean;
    return v < 0 ? 0 : v;
  }

  double chromaVariance() {
    if (count < 2) return 0;
    return chromaSqSum / count;
  }

  double brightFraction(double threshold) {
    if (count == 0) return 0;
    final n = threshold >= 0.85 ? brightCount85 : brightCount82;
    return n / count;
  }

  /// Simple redness index — relative R weight in the average color.
  double rednessIndex() {
    if (count == 0) return 0;
    final avgR = rSum / count;
    final avgG = gSum / count;
    final avgB = bSum / count;
    final total = avgR + avgG + avgB;
    if (total < 1) return 0;
    final rPct = avgR / total;
    // Healthy skin ~0.40-0.42; >0.45 trends towards red.
    return ((rPct - 0.42) * 8).clamp(0.0, 1.0);
  }
}

/// Honest, normalised match between a user and a product.
///
/// [score] is `achieved / possible × 100` over the signals where we actually
/// have data on BOTH sides (user profile + product card). It is NOT additive
/// from a base — an empty product card scores 0 over 0, not "50%".
///
/// [confidence] is how much of the user's evaluable signal space the product
/// actually filled. Low confidence (sparse product card or sparse profile)
/// means the score is unreliable; UIs should hide the number under ~40%.
///
/// [blocked] = hard knockout (skin-type mismatch). Such products must not be
/// auto-recommended — show only on direct view with a clear "not for you"
/// label.
///
/// [warnings] = soft caveats (e.g. potent active for sensitive skin). Surface
/// alongside the score; don't auto-recommend without a disclaimer.
class ProductMatch {
  ProductMatch({
    required this.score,
    required this.confidence,
    required this.reasons,
    required this.warnings,
    required this.blocked,
  });
  final int score;
  final int confidence;
  final List<String> reasons;
  final List<String> warnings;
  final bool blocked;

  /// Empty match (no profile data) — display as "no data" upstream.
  static final empty = ProductMatch(
    score: 0,
    confidence: 0,
    reasons: const [],
    warnings: const [],
    blocked: false,
  );
}

/// Weights of each scoring signal, in points out of 100. Only signals that
/// can be evaluated for THIS user contribute to the denominator — so a
/// non-sensitive user isn't capped below 100 because the sensitivity dimension
/// doesn't apply to them.
const int _wSkinType = 35;
const int _wSensitivity = 20;
const int _wProfileConcerns = 25;
const int _wScanConcerns = 15;
const int _wScanMetrics = 5;

ProductMatch computeMatch({
  required Map<String, dynamic> profile,
  required ProductRow product,
  Map<String, dynamic>? scan,
}) {
  final skinType = profile['skin_type'] as String?;
  final profileConcerns =
      (profile['concerns'] as List?)?.cast<String>() ?? const <String>[];
  final sensitivity = profile['sensitivity'] as String?;
  final scanConcerns =
      (scan?['concerns'] as List?)?.cast<String>() ?? const <String>[];

  // Per-user max: total weight of signals that could ever be evaluated given
  // what this user has filled in. Used to compute confidence (fraction of
  // user's evaluable signal space that the product actually filled in).
  var maxForUser = 0;
  if (skinType != null) maxForUser += _wSkinType;
  if (sensitivity == 'yes') maxForUser += _wSensitivity;
  if (profileConcerns.isNotEmpty) maxForUser += _wProfileConcerns;
  if (scanConcerns.isNotEmpty) maxForUser += _wScanConcerns;
  if (scan != null) maxForUser += _wScanMetrics;
  if (maxForUser == 0) return ProductMatch.empty;

  final reasons = <String>[];
  final warnings = <String>[];
  var blocked = false;
  var actuallyPossible = 0;
  var achieved = 0.0;

  // Skin type — hard knockout if mismatch (product is for the wrong skin).
  if (skinType != null && product.skinTypes.isNotEmpty) {
    actuallyPossible += _wSkinType;
    final matches = product.skinTypes.contains(skinType) ||
        product.skinTypes.contains('all');
    if (matches) {
      achieved += _wSkinType;
      reasons.add('Подходит для ${_skinTypeRu(skinType)} кожи');
    } else {
      blocked = true;
      warnings.add('Не для ${_skinTypeRu(skinType)} кожи');
    }
  }

  // Sensitivity safety. We score even when product flags are absent — a
  // product that's neither flagged "gentle" nor "active" gets half credit
  // (we genuinely don't know how strong it is).
  if (sensitivity == 'yes') {
    actuallyPossible += _wSensitivity;
    if (product.gentle) {
      achieved += _wSensitivity;
      reasons.add('Деликатная формула');
    } else if (product.isActive) {
      achieved += _wSensitivity * 0.2;
      warnings.add('⚠ Сильный актив — для чувствительной кожи рискованно');
    } else {
      achieved += _wSensitivity * 0.5;
    }
  }

  // Profile concerns: fraction of user's concerns the product addresses.
  if (profileConcerns.isNotEmpty && product.tags.isNotEmpty) {
    actuallyPossible += _wProfileConcerns;
    final hits = profileConcerns.where(product.tags.contains).toList();
    if (hits.isNotEmpty) {
      final frac = hits.length / profileConcerns.length;
      achieved += _wProfileConcerns * frac;
      reasons.add('Работает с: ${hits.map(_concernRu).join(', ')}');
    }
  }

  // Scan concerns: only credit tags that profile didn't already cover, to
  // avoid double-counting the same concern across two signals.
  if (scanConcerns.isNotEmpty && product.tags.isNotEmpty) {
    actuallyPossible += _wScanConcerns;
    final scanOnly =
        scanConcerns.where((c) => !profileConcerns.contains(c)).toList();
    if (scanOnly.isEmpty) {
      // All scan concerns already accounted for via profile → full credit.
      achieved += _wScanConcerns;
    } else {
      final hits = scanOnly.where(product.tags.contains).toList();
      if (hits.isNotEmpty) {
        final frac = hits.length / scanOnly.length;
        achieved += _wScanConcerns * frac;
        reasons.add('По скану: ${hits.map(_concernRu).join(', ')}');
      }
    }
  }

  // Scan metrics: per-metric, score 1 if (out-of-range && product addresses
  // it), 0 if (out-of-range && product ignores it), 0.5 if in range (neutral).
  if (scan != null) {
    actuallyPossible += _wScanMetrics;
    int? metric(String k) => (scan[k] as num?)?.toInt();
    final signals = <({bool need, bool covers})>[];
    final hydration = metric('hydration');
    if (hydration != null) {
      signals.add((
        need: hydration < 50,
        covers: product.tags.contains('dehydration'),
      ));
    }
    final sebum = metric('sebum');
    if (sebum != null) {
      signals.add((
        need: sebum > 60,
        covers: product.tags.contains('oiliness'),
      ));
    }
    final tone = metric('tone');
    if (tone != null) {
      signals.add((
        need: tone < 55,
        covers: product.tags.contains('dullness') ||
            product.tags.contains('pih'),
      ));
    }
    final pores = metric('pores');
    if (pores != null) {
      signals.add((
        need: pores < 50,
        covers: product.tags.contains('pores'),
      ));
    }
    if (signals.isNotEmpty) {
      var sum = 0.0;
      for (final s in signals) {
        if (!s.need) {
          sum += 0.5;
        } else if (s.covers) {
          sum += 1.0;
        }
      }
      achieved += _wScanMetrics * (sum / signals.length);
    } else {
      achieved += _wScanMetrics * 0.5;
    }
  }

  final score = actuallyPossible == 0
      ? 0
      : (achieved / actuallyPossible * 100).round().clamp(0, 100);
  final confidence =
      (actuallyPossible / maxForUser * 100).round().clamp(0, 100);

  return ProductMatch(
    score: score,
    confidence: confidence,
    reasons: reasons,
    warnings: warnings,
    blocked: blocked,
  );
}

String _skinTypeRu(String id) => switch (id) {
      'dry' => 'сухой',
      'oily' => 'жирной',
      'combo' => 'комбинированной',
      'normal' => 'нормальной',
      _ => 'твоей',
    };

class RoutineCompletionRepository {
  RoutineCompletionRepository(this.db);
  final Pool db;

  /// Returns set of "phase:step_index" strings completed for [day].
  Future<Set<String>> completedFor({
    required String userId,
    required DateTime day,
  }) async {
    final r = await db.execute(
      Sql.named('''
        SELECT phase, step_index FROM routine_completions
        WHERE user_id = @u AND day = @d
      '''),
      parameters: {'u': userId, 'd': day.toUtc()},
    );
    return r.map((row) => '${row[0]}:${row[1]}').toSet();
  }

  Future<void> check({
    required String userId,
    required DateTime day,
    required String phase,
    required int stepIndex,
    String? stepTitle,
  }) async {
    await db.execute(
      Sql.named('''
        INSERT INTO routine_completions (user_id, day, phase, step_index, step_title)
        VALUES (@u, @d, @p, @i, @t)
        ON CONFLICT (user_id, day, phase, step_index) DO UPDATE
          SET step_title = EXCLUDED.step_title, completed_at = now()
      '''),
      parameters: {
        'u': userId,
        'd': day.toUtc(),
        'p': phase,
        'i': stepIndex,
        't': stepTitle,
      },
    );
  }

  Future<void> uncheck({
    required String userId,
    required DateTime day,
    required String phase,
    required int stepIndex,
  }) async {
    await db.execute(
      Sql.named('''
        DELETE FROM routine_completions
        WHERE user_id = @u AND day = @d AND phase = @p AND step_index = @i
      '''),
      parameters: {'u': userId, 'd': day.toUtc(), 'p': phase, 'i': stepIndex},
    );
  }

  /// Returns the set of UTC dates between [since] and [until] (inclusive)
  /// on which the user checked at least one step. Used by the timeline
  /// endpoint to compute per-routine adherence without scanning the whole
  /// history per routine.
  Future<List<DateTime>> completionDaysInRange({
    required String userId,
    required DateTime since,
    required DateTime until,
  }) async {
    final r = await db.execute(
      Sql.named('''
        SELECT DISTINCT day FROM routine_completions
        WHERE user_id = @u AND day >= @s AND day <= @e
        ORDER BY day
      '''),
      parameters: {
        'u': userId,
        's': since.toUtc(),
        'e': until.toUtc(),
      },
    );
    return r.map((row) => row[0] as DateTime).toList();
  }

  /// Walks back from today, counting consecutive days with at least one completion.
  Future<int> streak(String userId) async {
    final r = await db.execute(
      Sql.named('''
        SELECT day FROM routine_completions
        WHERE user_id = @u
        GROUP BY day
        ORDER BY day DESC
        LIMIT 365
      '''),
      parameters: {'u': userId},
    );
    if (r.isEmpty) return 0;
    final days = r.map((row) => row[0] as DateTime).toList();
    final today = DateTime.utc(
        DateTime.now().toUtc().year,
        DateTime.now().toUtc().month,
        DateTime.now().toUtc().day);
    var expected = today;
    var count = 0;
    for (final d in days) {
      final dn = DateTime.utc(d.year, d.month, d.day);
      if (dn == expected) {
        count++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (dn.isBefore(expected)) {
        // gap — streak ends
        break;
      }
    }
    return count;
  }
}

String _concernRu(String id) => switch (id) {
      'acne' => 'акне',
      'pih' => 'постакне',
      'aging' => 'возрастные изменения',
      'dullness' => 'тусклый тон',
      'redness' => 'покраснения',
      'dehydration' => 'обезвоженность',
      'oiliness' => 'жирный блеск',
      'dryness' => 'сухость',
      'sensitivity' => 'чувствительность',
      'pores' => 'расширенные поры',
      _ => id,
    };

class ProfileRepository {
  ProfileRepository(this.db);
  final Pool db;

  Future<Map<String, dynamic>?> get(String userId) async {
    final r = await db.execute(
      Sql.named('''
        SELECT name, gender, skin_type, pores, concerns, acne_type, sensitivity,
               sensitivity_reaction, budget, extras, updated_at
        FROM skin_profiles WHERE user_id = @u
      '''),
      parameters: {'u': userId},
    );
    if (r.isEmpty) return null;
    final row = r.first;
    return {
      'name': row[0],
      'gender': row[1],
      'skin_type': row[2],
      'pores': row[3],
      'concerns': row[4],
      'acne_type': row[5],
      'sensitivity': row[6],
      'sensitivity_reaction': row[7],
      'budget': row[8],
      'extras': row[9],
      'updated_at': (row[10] as DateTime).toUtc().toIso8601String(),
    };
  }

  Future<void> upsert(String userId, Map<String, dynamic> profile) async {
    await db.execute(
      Sql.named('''
        INSERT INTO skin_profiles (user_id, name, gender, skin_type, pores, concerns,
            acne_type, sensitivity, sensitivity_reaction, budget, extras, updated_at)
        VALUES (@u, @n, @g, @st, @p, @c::jsonb, @at, @s, @sr, @b, @e::jsonb, now())
        ON CONFLICT (user_id) DO UPDATE SET
          name = EXCLUDED.name,
          gender = EXCLUDED.gender,
          skin_type = EXCLUDED.skin_type,
          pores = EXCLUDED.pores,
          concerns = EXCLUDED.concerns,
          acne_type = EXCLUDED.acne_type,
          sensitivity = EXCLUDED.sensitivity,
          sensitivity_reaction = EXCLUDED.sensitivity_reaction,
          budget = EXCLUDED.budget,
          extras = EXCLUDED.extras,
          updated_at = now()
      '''),
      parameters: {
        'u': userId,
        'n': profile['name'],
        'g': profile['gender'],
        'st': profile['skin_type'],
        'p': profile['pores'],
        'c': jsonEncode(profile['concerns'] ?? const []),
        'at': profile['acne_type'],
        's': profile['sensitivity'],
        'sr': profile['sensitivity_reaction'],
        'b': profile['budget'],
        'e': jsonEncode(profile['extras'] ?? const {}),
      },
    );
  }
}

class RoutineRepository {
  RoutineRepository(this.db);
  final Pool db;

  Future<String> create({
    required String userId,
    required String kind,
    required Map<String, dynamic> payload,
    double? confidence,
  }) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO routines (id, user_id, kind, payload, confidence)
        VALUES (@id, @u, @k, @p::jsonb, @c)
      '''),
      parameters: {
        'id': id,
        'u': userId,
        'k': kind,
        'p': jsonEncode(payload),
        'c': confidence,
      },
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> listForUser(String userId,
      {int limit = 20}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, kind, payload, confidence, created_at
        FROM routines WHERE user_id = @u
        ORDER BY created_at DESC LIMIT @lim
      '''),
      parameters: {'u': userId, 'lim': limit},
    );
    return r
        .map((row) => {
              'id': row[0],
              'kind': row[1],
              'payload': row[2],
              'confidence': row[3],
              'created_at': (row[4] as DateTime).toUtc().toIso8601String(),
            })
        .toList();
  }
}

class DermSessionRepository {
  DermSessionRepository(this.db);
  final Pool db;

  Future<String> create({
    required String userId,
    required Map<String, dynamic> profile,
    required List<dynamic> history,
    String? finalPhase,
    double? confidence,
  }) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO derm_sessions (id, user_id, profile, history, final_phase, confidence)
        VALUES (@id, @u, @p::jsonb, @h::jsonb, @fp, @c)
      '''),
      parameters: {
        'id': id,
        'u': userId,
        'p': jsonEncode(profile),
        'h': jsonEncode(history),
        'fp': finalPhase,
        'c': confidence,
      },
    );
    return id;
  }
}

class ChatMessageRepository {
  ChatMessageRepository(this.db);
  final Pool db;

  Future<void> append({
    required String userId,
    required String role,
    required String content,
    List<Map<String, dynamic>>? products,
  }) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO chat_messages (id, user_id, role, content, products)
        VALUES (@id, @u, @r, @c, @p)
      '''),
      parameters: {
        'id': id,
        'u': userId,
        'r': role,
        'c': content,
        'p': products == null ? null : jsonEncode(products),
      },
    );
  }

  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    int limit = 200,
  }) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, role, content, products, created_at
        FROM chat_messages
        WHERE user_id = @u
        ORDER BY created_at
        LIMIT @lim
      '''),
      parameters: {'u': userId, 'lim': limit},
    );
    return r.map((row) {
      final raw = row[3];
      return {
        'id': row[0],
        'role': row[1],
        'content': row[2],
        'products': raw is List ? raw : null,
        'created_at': (row[4] as DateTime).toUtc().toIso8601String(),
      };
    }).toList();
  }

  Future<void> clear(String userId) async {
    await db.execute(
      Sql.named('DELETE FROM chat_messages WHERE user_id = @u'),
      parameters: {'u': userId},
    );
  }
}

class NotificationRepository {
  NotificationRepository(this.db);
  final Pool db;

  Future<Map<String, dynamic>> create({
    required String userId,
    required String kind,
    required String title,
    String? body,
    Map<String, dynamic> payload = const {},
  }) async {
    final id = _uuid.v4();
    final r = await db.execute(
      Sql.named('''
        INSERT INTO notifications (id, user_id, kind, title, body, payload)
        VALUES (@id, @u, @k, @t, @b, @p::jsonb)
        RETURNING id, kind, title, body, payload, read_at, created_at
      '''),
      parameters: {
        'id': id,
        'u': userId,
        'k': kind,
        't': title,
        'b': body,
        'p': jsonEncode(payload),
      },
    );
    return _rowToJson(r.first);
  }

  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    int limit = 50,
  }) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, kind, title, body, payload, read_at, created_at
        FROM notifications
        WHERE user_id = @u
        ORDER BY created_at DESC
        LIMIT @lim
      '''),
      parameters: {'u': userId, 'lim': limit},
    );
    return r.map(_rowToJson).toList();
  }

  Future<int> unreadCount(String userId) async {
    final r = await db.execute(
      Sql.named(
          'SELECT count(*) FROM notifications WHERE user_id = @u AND read_at IS NULL'),
      parameters: {'u': userId},
    );
    return (r.first[0] as int);
  }

  /// Returns true if the notification existed and was owned by [userId].
  Future<bool> markRead({required String userId, required String id}) async {
    final r = await db.execute(
      Sql.named('''
        UPDATE notifications SET read_at = now()
        WHERE id = @id AND user_id = @u AND read_at IS NULL
        RETURNING id
      '''),
      parameters: {'id': id, 'u': userId},
    );
    return r.isNotEmpty;
  }

  Future<int> markAllRead(String userId) async {
    final r = await db.execute(
      Sql.named('''
        UPDATE notifications SET read_at = now()
        WHERE user_id = @u AND read_at IS NULL
      '''),
      parameters: {'u': userId},
    );
    return r.affectedRows;
  }

  Map<String, dynamic> _rowToJson(dynamic row) {
    final payload = row[4];
    return {
      'id': row[0],
      'kind': row[1],
      'title': row[2],
      'body': row[3],
      'payload': payload is Map ? payload.cast<String, dynamic>() : const {},
      'read_at': row[5] == null
          ? null
          : (row[5] as DateTime).toUtc().toIso8601String(),
      'created_at': (row[6] as DateTime).toUtc().toIso8601String(),
    };
  }
}
