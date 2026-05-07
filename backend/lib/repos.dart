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
    required Duration ttl,
  }) async {
    await db.execute(
      Sql.named('''
        INSERT INTO otp_codes (phone, code_hash, expires_at, attempts, created_at)
        VALUES (@p, @h, now() + (@s::text || ' seconds')::interval, 0, now())
        ON CONFLICT (phone) DO UPDATE
          SET code_hash = EXCLUDED.code_hash,
              expires_at = EXCLUDED.expires_at,
              attempts = 0,
              created_at = now()
      '''),
      parameters: {'p': phone, 'h': codeHash, 's': ttl.inSeconds.toString()},
    );
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

  Future<void> markLogin(String adminId) async {
    await db.execute(
      Sql.named('UPDATE admins SET last_login_at = now() WHERE id = @id'),
      parameters: {'id': adminId},
    );
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
      };
}

class ProductRepository {
  ProductRepository(this.db);
  final Pool db;

  static const _cols =
      'id, slug, brand, name, kind, description, price_rub, accent_color, '
      'ingredients, tags, skin_types, is_active_ingredient, gentle, '
      'routine_phase, status, photo IS NOT NULL';

  Future<List<ProductRow>> list({
    String? kind,
    String? concern,
    String? query,
    String? status,
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
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.execute(
      Sql.named(
          'SELECT $_cols FROM products $clause ORDER BY brand, name LIMIT @lim OFFSET @off'),
      parameters: params,
    );
    return rows.map(ProductRow.fromRow).toList();
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

  Future<({List<int> bytes, String mime})?> getPhoto(String id) async {
    final r = await db.execute(
      Sql.named('SELECT photo, photo_mime FROM products WHERE id = @id'),
      parameters: {'id': id},
    );
    if (r.isEmpty || r.first[0] == null) return null;
    return (
      bytes: r.first[0] as List<int>,
      mime: (r.first[1] as String?) ?? 'image/jpeg',
    );
  }

  Future<void> setPhoto(
      {required String id, required List<int> bytes, required String mime}) async {
    await db.execute(
      Sql.named(
          'UPDATE products SET photo = @b, photo_mime = @m WHERE id = @id'),
      parameters: {'id': id, 'b': bytes, 'm': mime},
    );
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
    );
    await db.execute(
      Sql.named('''
        UPDATE products SET
          brand = @brand, name = @name, kind = @kind, description = @desc,
          price_rub = @price, accent_color = @ac,
          ingredients = @ing::jsonb, tags = @tags::jsonb,
          skin_types = @st::jsonb,
          is_active_ingredient = @ai, gentle = @g, routine_phase = @rp,
          status = @status
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
      },
    );
    return updated;
  }

  Future<void> upsert(ProductRow p) async {
    await db.execute(
      Sql.named('''
        INSERT INTO products (
          id, slug, brand, name, kind, description, price_rub, accent_color,
          ingredients, tags, skin_types, is_active_ingredient, gentle,
          routine_phase, status
        ) VALUES (
          @id, @slug, @brand, @name, @kind, @desc, @price, @ac,
          @ing::jsonb, @tags::jsonb, @st::jsonb, @ai, @g, @rp, @status
        )
        ON CONFLICT (slug) DO UPDATE SET
          brand = EXCLUDED.brand, name = EXCLUDED.name, kind = EXCLUDED.kind,
          description = EXCLUDED.description, price_rub = EXCLUDED.price_rub,
          accent_color = EXCLUDED.accent_color, ingredients = EXCLUDED.ingredients,
          tags = EXCLUDED.tags, skin_types = EXCLUDED.skin_types,
          is_active_ingredient = EXCLUDED.is_active_ingredient,
          gentle = EXCLUDED.gentle, routine_phase = EXCLUDED.routine_phase,
          status = EXCLUDED.status
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
      },
    );
  }
}

class ShelfItem {
  ShelfItem({
    required this.product,
    required this.status,
    required this.addedAt,
    this.notes,
  });
  final ProductRow product;
  final String status;
  final DateTime addedAt;
  final String? notes;
}

class UserProductRepository {
  UserProductRepository(this.db);
  final Pool db;

  Future<List<ShelfItem>> list(String userId) async {
    final r = await db.execute(
      Sql.named('''
        SELECT p.id, p.slug, p.brand, p.name, p.kind, p.description,
               p.price_rub, p.accent_color, p.ingredients, p.tags,
               p.skin_types, p.is_active_ingredient, p.gentle, p.routine_phase,
               up.status, up.added_at, up.notes
        FROM user_products up
        JOIN products p ON p.id = up.product_id
        WHERE up.user_id = @u
        ORDER BY up.added_at DESC
      '''),
      parameters: {'u': userId},
    );
    return r.map((row) {
      return ShelfItem(
        product: ProductRow.fromRow(row.sublist(0, 14)),
        status: row[14] as String,
        addedAt: row[15] as DateTime,
        notes: row[16] as String?,
      );
    }).toList();
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
  }) async {
    final id = _uuid.v4();
    await db.execute(
      Sql.named('''
        INSERT INTO scans (id, user_id, photo, photo_mime, score, hydration,
                           sebum, tone, pores, zones, insight)
        VALUES (@id, @u, @p, @m, @sc, @h, @se, @t, @po, @z::jsonb, @i)
      '''),
      parameters: {
        'id': id,
        'u': userId,
        'p': photo,
        'm': mime,
        'sc': score,
        'h': hydration,
        'se': sebum,
        't': tone,
        'po': pores,
        'z': jsonEncode(zones),
        'i': insight,
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
    );
  }

  Future<ScanRow?> findById(
      {required String userId, required String id}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT id, user_id, score, hydration, sebum, tone, pores, zones,
               insight, created_at, photo IS NOT NULL
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
               insight, created_at, photo IS NOT NULL
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

  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      final px = image.getPixel(x, y);
      final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
      if (!_isSkinPixel(r, g, b)) continue;

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

  if (all.count < 1500) {
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

/// Compute 0..100 match between a user's profile and a product.
/// Returns score and a list of reasoning bullets.
({int score, List<String> reasons}) computeMatch({
  required Map<String, dynamic> profile,
  required ProductRow product,
}) {
  final reasons = <String>[];
  var score = 50;

  final skinType = profile['skin_type'] as String?;
  final concerns =
      (profile['concerns'] as List?)?.cast<String>() ?? const [];
  final sensitivity = profile['sensitivity'] as String?;

  // Skin type match.
  if (skinType != null) {
    if (product.skinTypes.contains(skinType) ||
        product.skinTypes.contains('all')) {
      score += 22;
      reasons.add('Подходит для ${_skinTypeRu(skinType)} кожи');
    } else if (product.skinTypes.isNotEmpty) {
      score -= 8;
    }
  }

  // Concerns overlap.
  final hits = concerns.where(product.tags.contains).toList();
  if (hits.isNotEmpty) {
    final delta = (hits.length * 9).clamp(0, 27);
    score += delta;
    reasons.add('Работает с: ${hits.map(_concernRu).join(', ')}');
  }

  // Sensitivity-friendly bonus / active warning.
  if (sensitivity == 'yes') {
    if (product.gentle) {
      score += 6;
      reasons.add('Деликатная формула');
    }
    if (product.isActive) {
      score -= 12;
      reasons.add('⚠ Содержит активы — вводи постепенно');
    }
  }

  return (
    score: score.clamp(0, 100),
    reasons: reasons,
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
      _ => id,
    };

class ProfileRepository {
  ProfileRepository(this.db);
  final Pool db;

  Future<Map<String, dynamic>?> get(String userId) async {
    final r = await db.execute(
      Sql.named('''
        SELECT name, skin_type, pores, concerns, acne_type, sensitivity,
               sensitivity_reaction, budget, extras, updated_at
        FROM skin_profiles WHERE user_id = @u
      '''),
      parameters: {'u': userId},
    );
    if (r.isEmpty) return null;
    final row = r.first;
    return {
      'name': row[0],
      'skin_type': row[1],
      'pores': row[2],
      'concerns': row[3],
      'acne_type': row[4],
      'sensitivity': row[5],
      'sensitivity_reaction': row[6],
      'budget': row[7],
      'extras': row[8],
      'updated_at': (row[9] as DateTime).toUtc().toIso8601String(),
    };
  }

  Future<void> upsert(String userId, Map<String, dynamic> profile) async {
    await db.execute(
      Sql.named('''
        INSERT INTO skin_profiles (user_id, name, skin_type, pores, concerns,
            acne_type, sensitivity, sensitivity_reaction, budget, extras, updated_at)
        VALUES (@u, @n, @st, @p, @c::jsonb, @at, @s, @sr, @b, @e::jsonb, now())
        ON CONFLICT (user_id) DO UPDATE SET
          name = EXCLUDED.name,
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
