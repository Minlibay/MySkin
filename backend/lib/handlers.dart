import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:uuid/uuid.dart';
import 'gigachat.dart';
import 'repos.dart';

final _rng = Random.secure();

String? normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 &&
      (digits.startsWith('7') || digits.startsWith('8'))) {
    return '+7${digits.substring(1)}';
  }
  if (digits.length == 10) return '+7$digits';
  return null;
}

String _generateCode() => List.generate(4, (_) => _rng.nextInt(10)).join();

String hashOtp(String phone, String code, String pepper) {
  return sha256.convert(utf8.encode('$pepper:$phone:$code')).toString();
}

Response jsonResponse(int status, Object body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

Future<bool> sendSmsViaSmsc({
  required String phone,
  required String code,
  required DotEnv env,
}) async {
  final login = env['SMSC_LOGIN'];
  final password = env['SMSC_PASSWORD'];
  if (login == null ||
      password == null ||
      login.isEmpty ||
      password.isEmpty) {
    stdout.writeln('[DEV SMS] $phone → code $code');
    return true;
  }
  final uri = Uri.https('smsc.ru', '/sys/send.php', {
    'login': login,
    'psw': password,
    'phones': phone,
    'mes': 'MySkin: ваш код $code',
    'fmt': '3',
    'charset': 'utf-8',
  });
  try {
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return false;
    final body = jsonDecode(resp.body);
    if (body is Map && body['error'] != null) {
      stderr.writeln('SMSC error: ${body['error']}');
      return false;
    }
    return true;
  } catch (e) {
    stderr.writeln('SMSC request failed: $e');
    return false;
  }
}

class AuthHandlers {
  AuthHandlers({
    required this.users,
    required this.sessions,
    required this.otps,
    required this.env,
  });

  final UserRepository users;
  final SessionRepository sessions;
  final OtpRepository otps;
  final DotEnv env;

  String get _pepper => env['OTP_PEPPER'] ?? 'unsalted';

  Router router() => Router()
    ..post('/auth/send-code', _sendCode)
    ..post('/auth/verify-code', _verifyCode)
    ..get('/auth/me', _me)
    ..post('/auth/logout', _logout);

  Future<Response> _sendCode(Request req) async {
    final raw = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final phone = normalizePhone(raw['phone'] as String? ?? '');
    if (phone == null) return jsonResponse(400, {'error': 'invalid_phone'});

    if (await otps.hasFreshCode(phone)) {
      return jsonResponse(429, {'error': 'too_many_requests'});
    }

    final code = _generateCode();
    final ok = await sendSmsViaSmsc(phone: phone, code: code, env: env);
    // Store the OTP regardless of SMS outcome: when the SMS provider fails
    // (e.g. balance gone) an admin can still relay the plaintext code to the
    // user via Codes page in the admin panel.
    await otps.upsert(
      phone: phone,
      codeHash: hashOtp(phone, code, _pepper),
      codePlain: code,
      ttl: const Duration(minutes: 5),
      smsSent: ok,
    );
    return jsonResponse(200, {
      'ok': true,
      'phone': phone,
      'expires_in_sec': 300,
      'sms_sent': ok,
    });
  }

  Future<Response> _verifyCode(Request req) async {
    final raw = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final phone = normalizePhone(raw['phone'] as String? ?? '');
    final code = (raw['code'] as String? ?? '').trim();
    if (phone == null || code.isEmpty) {
      return jsonResponse(400, {'error': 'invalid_request'});
    }
    final pending = await otps.get(phone);
    if (pending == null) {
      return jsonResponse(404, {'error': 'no_code_pending'});
    }
    if (pending.expiresAt.isBefore(DateTime.now())) {
      await otps.delete(phone);
      return jsonResponse(410, {'error': 'code_expired'});
    }
    if (pending.attempts >= 5) {
      await otps.delete(phone);
      return jsonResponse(429, {'error': 'too_many_attempts'});
    }
    if (hashOtp(phone, code, _pepper) != pending.codeHash) {
      await otps.incAttempts(phone);
      return jsonResponse(401, {'error': 'wrong_code'});
    }
    await otps.delete(phone);

    final user = await users.findOrCreateByPhone(phone);
    if (user.isBlocked) {
      return jsonResponse(403, {'error': 'user_blocked'});
    }
    await users.markLogin(user.id);
    final token = await sessions.create(
      user.id,
      userAgent: req.headers['user-agent'],
    );
    return jsonResponse(200, {
      'token': token,
      'user': user.toClientJson(),
    });
  }

  Future<Response> _me(Request req) async {
    final token = _bearer(req);
    if (token == null) return jsonResponse(401, {'error': 'unauthorized'});
    final user = await sessions.userForToken(token);
    if (user == null) return jsonResponse(401, {'error': 'unauthorized'});
    if (user.isBlocked) return jsonResponse(403, {'error': 'user_blocked'});
    return jsonResponse(200, {'user': user.toClientJson()});
  }

  Future<Response> _logout(Request req) async {
    final token = _bearer(req);
    if (token != null) await sessions.delete(token);
    return jsonResponse(200, {'ok': true});
  }
}

class AdminHandlers {
  AdminHandlers({
    required this.admins,
    required this.users,
    required this.stats,
    required this.profiles,
    required this.scans,
    required this.shelf,
    required this.products,
    required this.otps,
    required this.appSettings,
  });

  final AdminRepository admins;
  final UserRepository users;
  final StatsRepository stats;
  final ProfileRepository profiles;
  final ScanRepository scans;
  final UserProductRepository shelf;
  final ProductRepository products;
  final OtpRepository otps;
  final AppSettingsRepository appSettings;

  static const _uuid = Uuid();

  Router router() => Router()
    ..post('/admin/login', _login)
    ..get('/admin/users', _withAdmin(_listUsers))
    ..get('/admin/users/<id>', _withAdmin(_getUser))
    ..get('/admin/users/<id>/scans', _withAdmin(_getUserScans))
    ..get('/admin/users/<id>/shelf', _withAdmin(_getUserShelf))
    ..post('/admin/users/<id>/block', _withAdmin(_block))
    ..post('/admin/users/<id>/unblock', _withAdmin(_unblock))
    ..get('/admin/stats', _withAdmin(_stats))
    ..get('/admin/products', _withAdmin(_listProducts))
    ..post('/admin/products', _withAdmin(_createProduct))
    ..patch('/admin/products/<id>', _withAdmin(_updateProduct))
    ..delete('/admin/products/<id>', _withAdmin(_deleteProduct))
    ..post('/admin/products/<id>/photo', _withAdmin(_uploadProductPhoto))
    ..get('/admin/pending-codes', _withAdmin(_pendingCodes))
    ..get('/admin/settings/gigachat', _withAdmin(_getGigaSettings))
    ..put('/admin/settings/gigachat', _withAdmin(_setGigaSettings))
    ..get('/admin/settings/legal', _withAdmin(_getLegal))
    ..put('/admin/settings/legal', _withAdmin(_setLegal));

  Handler _withAdmin(Handler inner) => (Request req) async {
        final token = _bearer(req);
        if (token == null || !await admins.isValidToken(token)) {
          return jsonResponse(401, {'error': 'unauthorized'});
        }
        return inner(req);
      };

  Future<Response> _login(Request req) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final login = (body['login'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    if (login.isEmpty || password.isEmpty) {
      return jsonResponse(400, {'error': 'invalid_request'});
    }
    final admin = await admins.findByLogin(login);
    if (admin == null || !BCrypt.checkpw(password, admin.passwordHash)) {
      return jsonResponse(401, {'error': 'invalid_credentials'});
    }
    await admins.markLogin(admin.id);
    final token = await admins.createSession(admin.id);
    return jsonResponse(200, {'token': token});
  }

  Future<Response> _listUsers(Request req) async {
    final qp = req.url.queryParameters;
    final limit = int.tryParse(qp['limit'] ?? '') ?? 20;
    final offset = int.tryParse(qp['offset'] ?? '') ?? 0;
    final query = qp['q'];
    final page = await users.page(
      limit: limit.clamp(1, 100),
      offset: offset.clamp(0, 1000000),
      query: query,
    );
    return jsonResponse(200, {
      'items': page.items.map((u) => u.toAdminJson()).toList(),
      'total': page.total,
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> _block(Request req) async =>
      _setBlocked(req.params['id']!, true);
  Future<Response> _unblock(Request req) async =>
      _setBlocked(req.params['id']!, false);

  Future<Response> _setBlocked(String id, bool blocked) async {
    final user = await users.findById(id);
    if (user == null) return jsonResponse(404, {'error': 'not_found'});
    await users.setBlocked(id, blocked);
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _stats(Request req) async =>
      jsonResponse(200, await stats.overview());

  Future<Response> _getGigaSettings(Request req) async {
    final m = await appSettings.getMany(
        const ['gigachat_chat_model', 'gigachat_vision_model']);
    return jsonResponse(200, {
      'chat_model': m['gigachat_chat_model'],
      'vision_model': m['gigachat_vision_model'],
      // Suggested choices the admin can pick from; the field accepts any
      // string so new model names work without a code change.
      'available_models': const [
        'GigaChat',
        'GigaChat-Plus',
        'GigaChat-Pro',
        'GigaChat-Max',
        'GigaChat-2-Lite',
        'GigaChat-2-Pro',
        'GigaChat-2-Max',
      ],
    });
  }

  Future<Response> _setGigaSettings(Request req) async {
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final chat = (body['chat_model'] as String?)?.trim();
    final vision = (body['vision_model'] as String?)?.trim();
    if (chat != null && chat.isNotEmpty) {
      await appSettings.set('gigachat_chat_model', chat);
    }
    if (vision != null && vision.isNotEmpty) {
      await appSettings.set('gigachat_vision_model', vision);
    }
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _getLegal(Request req) async {
    final m = await appSettings.getMany(
        const ['legal_terms', 'legal_privacy', 'legal_consent']);
    return jsonResponse(200, {
      'terms': m['legal_terms'] ?? '',
      'privacy': m['legal_privacy'] ?? '',
      'consent': m['legal_consent'] ?? '',
    });
  }

  Future<Response> _setLegal(Request req) async {
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final mapping = {
      'legal_terms': body['terms'] as String?,
      'legal_privacy': body['privacy'] as String?,
      'legal_consent': body['consent'] as String?,
    };
    for (final entry in mapping.entries) {
      final v = entry.value;
      if (v != null) await appSettings.set(entry.key, v);
    }
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _pendingCodes(Request req) async {
    final list = await otps.listPending();
    return jsonResponse(200, {
      'items': list
          .map((it) => {
                'phone': it.phone,
                'code': it.code,
                'sms_sent': it.smsSent,
                'attempts': it.attempts,
                'created_at': it.createdAt.toUtc().toIso8601String(),
                'expires_at': it.expiresAt.toUtc().toIso8601String(),
              })
          .toList(),
    });
  }

  Future<Response> _getUser(Request req) async {
    final id = req.params['id']!;
    final user = await users.findById(id);
    if (user == null) return jsonResponse(404, {'error': 'not_found'});
    final profile = await profiles.get(id);
    final shelfItems = await shelf.list(id);
    final scanList = await scans.listForUser(id, limit: 10);
    return jsonResponse(200, {
      'user': user.toAdminJson(),
      'profile': profile,
      'shelf_count': shelfItems.length,
      'scans_count': scanList.length,
      'last_scan': scanList.isNotEmpty ? scanList.first.toJson() : null,
    });
  }

  Future<Response> _getUserScans(Request req) async {
    final id = req.params['id']!;
    final list = await scans.listForUser(id, limit: 50);
    return jsonResponse(200,
        {'items': list.map((s) => s.toJson()).toList()});
  }

  Future<Response> _getUserShelf(Request req) async {
    final id = req.params['id']!;
    final list = await shelf.list(id);
    return jsonResponse(200, {
      'items': list
          .map((it) => {
                ...it.product.toJson(),
                'status': it.status,
                'added_at': it.addedAt.toUtc().toIso8601String(),
                'notes': it.notes,
              })
          .toList(),
    });
  }

  Future<Response> _listProducts(Request req) async {
    final qp = req.url.queryParameters;
    final items = await products.list(
      kind: qp['kind'],
      query: qp['q'],
      limit: int.tryParse(qp['limit'] ?? '') ?? 200,
      offset: int.tryParse(qp['offset'] ?? '') ?? 0,
    );
    return jsonResponse(
        200, {'items': items.map((p) => p.toJson()).toList()});
  }

  Future<Response> _createProduct(Request req) async {
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final missing = ['slug', 'brand', 'name', 'kind']
        .where((f) => (body[f] as String?)?.trim().isEmpty ?? true)
        .toList();
    if (missing.isNotEmpty) {
      return jsonResponse(
          400, {'error': 'missing_fields', 'fields': missing});
    }
    final existing = await products.findBySlug(body['slug'] as String);
    if (existing != null) {
      return jsonResponse(409, {'error': 'slug_taken'});
    }
    final p = ProductRow(
      id: _uuid.v4(),
      slug: (body['slug'] as String).trim(),
      brand: (body['brand'] as String).trim(),
      name: (body['name'] as String).trim(),
      kind: (body['kind'] as String).trim(),
      description: (body['description'] as String?)?.trim() ?? '',
      priceRub: (body['price_rub'] as num?)?.toInt() ?? 0,
      accentColor:
          (body['accent_color'] as String?)?.trim() ?? '#D98FA3',
      ingredients:
          ((body['ingredients'] as List?) ?? const []).cast<String>(),
      tags: ((body['tags'] as List?) ?? const []).cast<String>(),
      skinTypes:
          ((body['skin_types'] as List?) ?? const []).cast<String>(),
      isActive: body['is_active'] as bool? ?? false,
      gentle: body['gentle'] as bool? ?? false,
      routinePhase:
          (body['routine_phase'] as String?)?.trim() ?? 'any',
      status: (body['status'] as String?)?.trim() ?? 'draft',
    );
    await products.upsert(p);
    return jsonResponse(200, p.toJson());
  }

  Future<Response> _uploadProductPhoto(Request req) async {
    final id = req.params['id']!;
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final b64 = body['photo_b64'] as String?;
    final mime = body['mime'] as String? ?? 'image/jpeg';
    if (b64 == null || b64.isEmpty) {
      return jsonResponse(400, {'error': 'no_photo'});
    }
    List<int> bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return jsonResponse(400, {'error': 'invalid_photo'});
    }
    if (bytes.length > 6 * 1024 * 1024) {
      return jsonResponse(413, {'error': 'photo_too_large'});
    }
    final existing = await products.findById(id);
    if (existing == null) return jsonResponse(404, {'error': 'not_found'});
    await products.setPhoto(id: id, bytes: bytes, mime: mime);
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _updateProduct(Request req) async {
    final id = req.params['id']!;
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final updated = await products.update(id, body);
    if (updated == null) return jsonResponse(404, {'error': 'not_found'});
    return jsonResponse(200, updated.toJson());
  }

  Future<Response> _deleteProduct(Request req) async {
    final id = req.params['id']!;
    await products.delete(id);
    return jsonResponse(200, {'ok': true});
  }
}

class AiHandlers {
  AiHandlers({
    required this.sessions,
    required this.giga,
    required this.products,
    required this.profiles,
    required this.scans,
    required this.appSettings,
    required this.chatMessages,
  });
  final SessionRepository sessions;
  final GigaChatClient giga;
  final ProductRepository products;
  final ProfileRepository profiles;
  final ScanRepository scans;
  final AppSettingsRepository appSettings;
  final ChatMessageRepository chatMessages;

  Router router() => Router()
    ..post('/ai/generate-routine', _withUser(_generate))
    ..post('/ai/derm-analyze', _withUser(_dermAnalyze))
    ..post('/ai/chat', _withUser(_chat));

  Handler _withUser(Future<Response> Function(Request, UserRow) inner) =>
      (Request req) async {
        final token = _bearer(req);
        if (token == null) return jsonResponse(401, {'error': 'unauthorized'});
        final user = await sessions.userForToken(token);
        if (user == null) return jsonResponse(401, {'error': 'unauthorized'});
        if (user.isBlocked) {
          return jsonResponse(403, {'error': 'user_blocked'});
        }
        return inner(req, user);
      };

  Future<Response> _generate(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final profile = body['profile'] as Map<String, dynamic>? ?? const {};
    final checkIn = body['check_in'] as Map<String, dynamic>?;
    try {
      // Optional same-day check-in: mood, what they notice, what they want
      // today. Feeds into the prompt so a routine generated right now reflects
      // 'кожа сегодня тонкая, хочу успокоить', not just the static profile.
      final userMsg = StringBuffer('Данные пользователя:\n');
      userMsg.write(jsonEncode(profile));
      if (checkIn != null && checkIn.isNotEmpty) {
        userMsg.write('\n\nСостояние сегодня (опрос пользователя): ');
        userMsg.write(jsonEncode(checkIn));
        userMsg.write('\nУчти это в подборе шагов и тоне комментариев.');
      }
      final raw = await giga.chat(
        systemPrompt: standardSystemPrompt,
        userMessage: userMsg.toString(),
      );
      return jsonResponse(200, parseJsonReply(raw));
    } on GigaChatException catch (e) {
      stderr.writeln('GigaChat /generate failed: $e');
      return jsonResponse(502, {'error': 'ai_failed', 'message': e.message});
    } on FormatException catch (e) {
      return jsonResponse(502, {'error': 'ai_bad_json', 'message': '$e'});
    }
  }

  Future<Response> _chat(Request req, UserRow user) async {
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final raw = (body['messages'] as List?) ?? const [];
    final messages = <Map<String, dynamic>>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final role = m['role'] as String?;
      final content = m['content'] as String?;
      if (role == null || content == null) continue;
      if (!const {'user', 'assistant'}.contains(role)) continue;
      messages.add({'role': role, 'content': content});
    }
    if (messages.length > 30) {
      messages.removeRange(0, messages.length - 30);
    }
    if (messages.isEmpty || messages.last['role'] != 'user') {
      return jsonResponse(400, {'error': 'last_message_must_be_user'});
    }

    // Pre-compute top-matched products for this user so Лина can mention
    // them and the frontend can render them as a strip beside her reply.
    final profile = await profiles.get(user.id) ?? <String, dynamic>{};
    final catalog =
        await products.list(status: 'published', limit: 200);
    final scored = <({ProductRow p, int score, List<String> reasons})>[];
    for (final p in catalog) {
      final m = computeMatch(profile: profile, product: p);
      scored.add((p: p, score: m.score, reasons: m.reasons));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(8).toList();

    final catalogHint = top
        .map((e) => {
              'id': e.p.id,
              'brand': e.p.brand,
              'name': e.p.name,
              'kind': e.p.kind,
              'tags': e.p.tags,
              'match_score': e.score,
            })
        .toList();
    final recentScans = await scans.listForUser(user.id, limit: 1);
    final scanHint = recentScans.isEmpty
        ? null
        : {
            'score': recentScans.first.score,
            'hydration': recentScans.first.hydration,
            'sebum': recentScans.first.sebum,
            'tone': recentScans.first.tone,
            'pores': recentScans.first.pores,
            'zones': recentScans.first.zones,
            'insight': recentScans.first.insight,
            'created_at':
                recentScans.first.createdAt.toUtc().toIso8601String(),
          };

    final enrichedSystem = [
      linaChatSystemPrompt,
      '',
      'Профиль пользователя (используй для персонализации ответов, '
          'учитывай тип кожи, чувствительность, цели и бюджет; '
          'обращайся по имени, если оно указано):',
      jsonEncode(profile),
      if (scanHint != null) ...[
        '',
        'Последний скан кожи пользователя (метрики 0-100, бери в расчёт):',
        jsonEncode(scanHint),
      ],
      '',
      'Доступный каталог (топ-${top.length} '
          'по соответствию профилю пользователя):',
      jsonEncode(catalogHint),
      '',
      'Когда уместно, упоминай эти продукты по бренду и названию. '
          'Не выдумывай продукты, которых нет в списке.',
    ].join('\n');

    try {
      final chatModel = await appSettings.get('gigachat_chat_model') ??
          giga.chatModel;
      final reply = await giga.chatWithMessages(
        systemPrompt: enrichedSystem,
        messages: messages,
        model: chatModel,
      );

      // Only surface products when Лина explicitly flagged this turn as a
      // product recommendation. Falls back to a regex sniff if the JSON
      // body is malformed but contains the flag verbatim.
      var showProducts = false;
      try {
        final parsed = parseJsonReply(reply);
        showProducts = parsed['show_products'] == true;
      } catch (_) {
        showProducts =
            RegExp(r'"show_products"\s*:\s*true').hasMatch(reply);
      }

      final recommended = showProducts
          ? top
              .where((e) => e.score >= 40)
              .take(5)
              .map((e) => {
                    ...e.p.toJson(),
                    'match_score': e.score,
                    'match_reasons': e.reasons,
                  })
              .toList()
          : const <Map<String, dynamic>>[];

      // Persist both the user's last message and Лина's reply so the chat
      // history survives app restarts. Best-effort — never blocks the response.
      try {
        await chatMessages.append(
          userId: user.id,
          role: 'user',
          content: messages.last['content'] as String,
        );
        await chatMessages.append(
          userId: user.id,
          role: 'assistant',
          content: reply.trim(),
          products: recommended.isEmpty ? null : recommended,
        );
      } catch (e) {
        stderr.writeln('chat persist failed: $e');
      }

      return jsonResponse(200, {
        'reply': reply.trim(),
        'recommended_products': recommended,
      });
    } on GigaChatException catch (e) {
      stderr.writeln('GigaChat /chat failed: $e');
      return jsonResponse(502, {'error': 'ai_failed', 'message': e.message});
    }
  }

  Future<Response> _dermAnalyze(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final profile = body['profile'] as Map<String, dynamic>? ?? const {};
    final history = body['history'] as List? ?? const [];
    try {
      final raw = await giga.chat(
        systemPrompt: dermSystemPrompt,
        userMessage: jsonEncode({
          'user_data': profile,
          'clarification_history': history,
        }),
      );
      return jsonResponse(200, parseJsonReply(raw));
    } on GigaChatException catch (e) {
      stderr.writeln('GigaChat /derm failed: $e');
      return jsonResponse(502, {'error': 'ai_failed', 'message': e.message});
    } on FormatException catch (e) {
      return jsonResponse(502, {'error': 'ai_bad_json', 'message': '$e'});
    }
  }
}

ScanAnalysis _mergeAiAnalysis(ScanAnalysis local, Map<String, dynamic> ai) {
  int clamp(num? v, int fallback) {
    if (v == null) return fallback;
    final i = v.toInt();
    return i.clamp(0, 100);
  }

  final aiZones = (ai['zones'] as Map?) ?? const {};
  final mergedZones = <String, int>{};
  for (final k in const ['forehead', 'nose', 'left_cheek', 'right_cheek', 'chin']) {
    mergedZones[k] = clamp(aiZones[k] as num?, local.zones[k] ?? 60);
  }
  final aiWarnings =
      ((ai['quality_warnings'] as List?) ?? const []).cast<String>();
  return ScanAnalysis(
    score: clamp(ai['score'] as num?, local.score),
    hydration: clamp(ai['hydration'] as num?, local.hydration),
    sebum: clamp(ai['sebum'] as num?, local.sebum),
    tone: clamp(ai['tone'] as num?, local.tone),
    pores: clamp(ai['pores'] as num?, local.pores),
    zones: mergedZones,
    insight: (ai['insight'] as String?)?.trim().isNotEmpty == true
        ? (ai['insight'] as String).trim()
        : local.insight,
    qualityWarnings:
        aiWarnings.isNotEmpty ? aiWarnings : local.qualityWarnings,
    meta: {
      ...local.meta,
      'source': 'gigachat-vision',
      if (ai['concerns'] is List) 'ai_concerns': ai['concerns'],
    },
    faceGeom: local.faceGeom,
  );
}

class ScanHandlers {
  ScanHandlers({
    required this.sessions,
    required this.scans,
    required this.profiles,
    required this.appSettings,
    required this.notifications,
    this.giga,
  });

  final SessionRepository sessions;
  final ScanRepository scans;
  final ProfileRepository profiles;
  final AppSettingsRepository appSettings;
  final NotificationRepository notifications;
  final GigaChatClient? giga;

  Router router() => Router()
    ..post('/me/scans', _withUser(_create))
    ..get('/me/scans', _withUser(_list))
    ..get('/me/scans/<id>', _withUser(_detail))
    ..get('/me/scans/<id>/photo', _withUser(_photo));

  Handler _withUser(Future<Response> Function(Request, UserRow) inner) =>
      (Request req) async {
        final token = _bearer(req);
        if (token == null) return jsonResponse(401, {'error': 'unauthorized'});
        final user = await sessions.userForToken(token);
        if (user == null) return jsonResponse(401, {'error': 'unauthorized'});
        if (user.isBlocked) {
          return jsonResponse(403, {'error': 'user_blocked'});
        }
        return inner(req, user);
      };

  Future<Response> _create(Request req, UserRow user) async {
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final b64 = body['photo_b64'] as String?;
    final mime = body['mime'] as String? ?? 'image/jpeg';
    List<int>? bytes;
    if (b64 != null && b64.isNotEmpty) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {
        return jsonResponse(400, {'error': 'invalid_photo'});
      }
      if (bytes.length > 6 * 1024 * 1024) {
        return jsonResponse(413, {'error': 'photo_too_large'});
      }
    }
    final profile = await profiles.get(user.id) ?? <String, dynamic>{};
    var analysis = analyzeScan(
      photoBytes: bytes ?? [DateTime.now().millisecondsSinceEpoch & 0xFF],
      profile: profile,
    );
    // If GigaChat (vision) is available and a photo was supplied, prefer the
    // AI-derived metrics. On any error we silently keep the local pixel
    // analysis so the user still gets a result.
    if (giga != null && bytes != null && bytes.length > 1000) {
      try {
        final visionModel =
            await appSettings.get('gigachat_vision_model');
        final raw = await giga!.analyzePhoto(
          systemPrompt: visionScanSystemPrompt,
          userText:
              'Проанализируй кожу на этой селфи. Профиль: ${jsonEncode(profile)}',
          photoBytes: bytes,
          mime: mime,
          model: visionModel,
        );
        final j = parseJsonReply(raw);
        analysis = _mergeAiAnalysis(analysis, j);
      } catch (e) {
        stderr.writeln('Vision scan failed, using local analysis: $e');
      }
    }
    // Prefer the client's ML Kit bbox (precise face detector) over the
    // backend's skin-colour heuristic, which often blooms to cover the whole
    // photo on well-lit selfies. Validate before accepting.
    Map<String, dynamic>? faceGeom = analysis.faceGeom;
    final clientBbox = body['face_bbox'];
    if (clientBbox is List && clientBbox.length == 4) {
      final v = clientBbox.map((e) => (e as num).toDouble()).toList();
      final ok = v.every((e) => e >= 0 && e <= 1) &&
          v[2] > v[0] &&
          v[3] > v[1] &&
          (v[2] - v[0]) < 0.95 &&
          (v[3] - v[1]) < 0.95;
      if (ok) {
        faceGeom = {'bbox': v};
      }
    }
    final scan = await scans.create(
      userId: user.id,
      photo: bytes,
      mime: mime,
      score: analysis.score,
      hydration: analysis.hydration,
      sebum: analysis.sebum,
      tone: analysis.tone,
      pores: analysis.pores,
      zones: analysis.zones,
      insight: analysis.insight,
      faceGeom: faceGeom,
    );
    // Drop a notification into the inbox so the bell shows the unread dot.
    // Failure here must never block the scan response.
    try {
      await notifications.create(
        userId: user.id,
        kind: 'scan_ready',
        title: 'Анализ кожи готов',
        body: analysis.insight,
        payload: {'scan_id': scan.id},
      );
    } catch (e) {
      stderr.writeln('notification scan_ready failed: $e');
    }
    // Augment response with non-persisted analysis metadata.
    return jsonResponse(200, {
      ...scan.toJson(),
      'quality_warnings': analysis.qualityWarnings,
      'analysis_meta': analysis.meta,
    });
  }

  Future<Response> _list(Request req, UserRow user) async {
    final items = await scans.listForUser(user.id);
    return jsonResponse(
        200, {'items': items.map((s) => s.toJson()).toList()});
  }

  Future<Response> _detail(Request req, UserRow user) async {
    final id = req.params['id']!;
    final scan = await scans.findById(userId: user.id, id: id);
    if (scan == null) return jsonResponse(404, {'error': 'not_found'});
    return jsonResponse(200, scan.toJson());
  }

  Future<Response> _photo(Request req, UserRow user) async {
    final id = req.params['id']!;
    final p = await scans.getPhoto(userId: user.id, id: id);
    if (p == null) return jsonResponse(404, {'error': 'no_photo'});
    return Response.ok(
      p.bytes,
      headers: {
        'content-type': p.mime,
        'cache-control': 'private, max-age=86400',
      },
    );
  }
}

class CatalogHandlers {
  CatalogHandlers({
    required this.sessions,
    required this.products,
    required this.shelf,
    required this.profiles,
  });

  final SessionRepository sessions;
  final ProductRepository products;
  final UserProductRepository shelf;
  final ProfileRepository profiles;

  Router router() => Router()
    ..get('/catalog', _withUser(_list))
    ..get('/catalog/<slug>', _withUser(_detail))
    ..get('/products/<id>/photo', _photo) // public for mobile + admin previews
    ..get('/me/shelf', _withUser(_shelf))
    ..put('/me/shelf/<productId>', _withUser(_addToShelf))
    ..delete('/me/shelf/<productId>', _withUser(_removeFromShelf));

  Handler _withUser(Future<Response> Function(Request, UserRow) inner) =>
      (Request req) async {
        final token = _bearer(req);
        if (token == null) return jsonResponse(401, {'error': 'unauthorized'});
        final user = await sessions.userForToken(token);
        if (user == null) return jsonResponse(401, {'error': 'unauthorized'});
        if (user.isBlocked) {
          return jsonResponse(403, {'error': 'user_blocked'});
        }
        return inner(req, user);
      };

  Future<Response> _list(Request req, UserRow user) async {
    final qp = req.url.queryParameters;
    final items = await products.list(
      kind: qp['kind'],
      concern: qp['concern'],
      query: qp['q'],
      status: 'published',
      limit: int.tryParse(qp['limit'] ?? '') ?? 60,
      offset: int.tryParse(qp['offset'] ?? '') ?? 0,
    );
    final profile = await profiles.get(user.id) ?? <String, dynamic>{};
    return jsonResponse(200, {
      'items': items.map((p) {
        final m = computeMatch(profile: profile, product: p);
        return {
          ...p.toJson(),
          'match_score': m.score,
          'match_reasons': m.reasons,
        };
      }).toList(),
    });
  }

  Future<Response> _photo(Request req) async {
    final id = req.params['id']!;
    final p = await products.getPhoto(id);
    if (p == null) return jsonResponse(404, {'error': 'no_photo'});
    return Response.ok(
      p.bytes,
      headers: {
        'content-type': p.mime,
        'cache-control': 'public, max-age=86400',
      },
    );
  }

  Future<Response> _detail(Request req, UserRow user) async {
    final slug = req.params['slug']!;
    final p = await products.findBySlug(slug, publishedOnly: true);
    if (p == null) return jsonResponse(404, {'error': 'not_found'});
    final profile = await profiles.get(user.id) ?? <String, dynamic>{};
    final m = computeMatch(profile: profile, product: p);
    return jsonResponse(200, {
      ...p.toJson(),
      'match_score': m.score,
      'match_reasons': m.reasons,
    });
  }

  Future<Response> _shelf(Request req, UserRow user) async {
    final items = await shelf.list(user.id);
    return jsonResponse(200, {
      'items': items
          .map((it) => {
                ...it.product.toJson(),
                'status': it.status,
                'added_at': it.addedAt.toUtc().toIso8601String(),
                'notes': it.notes,
              })
          .toList(),
    });
  }

  Future<Response> _addToShelf(Request req, UserRow user) async {
    final productId = req.params['productId']!;
    final body =
        jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final status = (body['status'] as String? ?? 'have').trim();
    if (!const {'have', 'wishlist', 'finished'}.contains(status)) {
      return jsonResponse(400, {'error': 'invalid_status'});
    }
    final p = await products.findById(productId);
    if (p == null) return jsonResponse(404, {'error': 'not_found'});
    await shelf.upsert(
      userId: user.id,
      productId: productId,
      status: status,
      notes: body['notes'] as String?,
    );
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _removeFromShelf(Request req, UserRow user) async {
    final productId = req.params['productId']!;
    await shelf.remove(userId: user.id, productId: productId);
    return jsonResponse(200, {'ok': true});
  }
}

String? _bearer(Request req) {
  final h = req.headers['authorization'] ?? '';
  if (!h.startsWith('Bearer ')) return null;
  return h.substring(7);
}

class MeHandlers {
  MeHandlers({
    required this.sessions,
    required this.profiles,
    required this.routines,
    required this.dermSessions,
    required this.completions,
    required this.users,
    required this.scans,
    required this.chatMessages,
  });

  final SessionRepository sessions;
  final ProfileRepository profiles;
  final RoutineRepository routines;
  final DermSessionRepository dermSessions;
  final RoutineCompletionRepository completions;
  final UserRepository users;
  final ScanRepository scans;
  final ChatMessageRepository chatMessages;

  Router router() => Router()
    ..get('/me/profile', _withUser(_getProfile))
    ..put('/me/profile', _withUser(_putProfile))
    ..get('/me/routines', _withUser(_listRoutines))
    ..post('/me/routines', _withUser(_createRoutine))
    ..post('/me/derm-sessions', _withUser(_createDermSession))
    ..get('/me/today', _withUser(_today))
    ..post('/me/today/check', _withUser(_checkStep))
    ..post('/me/today/uncheck', _withUser(_uncheckStep))
    ..get('/me/settings', _withUser(_getSettings))
    ..put('/me/settings', _withUser(_putSettings))
    ..get('/me/export', _withUser(_export))
    ..delete('/me/account', _withUser(_deleteAccount))
    ..get('/me/progress', _withUser(_progress))
    ..get('/me/chat', _withUser(_getChat))
    ..delete('/me/chat', _withUser(_clearChat));

  Handler _withUser(Future<Response> Function(Request, UserRow) inner) =>
      (Request req) async {
        final token = _bearer(req);
        if (token == null) return jsonResponse(401, {'error': 'unauthorized'});
        final user = await sessions.userForToken(token);
        if (user == null) return jsonResponse(401, {'error': 'unauthorized'});
        if (user.isBlocked) {
          return jsonResponse(403, {'error': 'user_blocked'});
        }
        return inner(req, user);
      };

  Future<Response> _getProfile(Request req, UserRow user) async {
    final p = await profiles.get(user.id);
    if (p == null) return jsonResponse(404, {'error': 'no_profile'});
    return jsonResponse(200, p);
  }

  Future<Response> _putProfile(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    await profiles.upsert(user.id, body);
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _listRoutines(Request req, UserRow user) async {
    final items = await routines.listForUser(user.id);
    return jsonResponse(200, {'items': items});
  }

  Future<Response> _createRoutine(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final kind = body['kind'] as String? ?? 'standard';
    final payload = body['payload'] as Map<String, dynamic>? ?? const {};
    final confidence = (body['confidence'] as num?)?.toDouble();
    final id = await routines.create(
      userId: user.id,
      kind: kind,
      payload: payload,
      confidence: confidence,
    );
    return jsonResponse(200, {'id': id});
  }

  Future<Response> _createDermSession(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final id = await dermSessions.create(
      userId: user.id,
      profile: body['profile'] as Map<String, dynamic>? ?? const {},
      history: body['history'] as List? ?? const [],
      finalPhase: body['final_phase'] as String?,
      confidence: (body['confidence'] as num?)?.toDouble(),
    );
    return jsonResponse(200, {'id': id});
  }

  Future<Response> _today(Request req, UserRow user) async {
    // Pull the recent few and pick the freshest one with non-empty steps —
    // skips routines that the AI returned blank (saw this when GigaChat
    // returned both follow-up + empty schema).
    final recent = await routines.listForUser(user.id, limit: 5);
    Map<String, dynamic>? latest;
    for (final r in recent) {
      final p = r['payload'];
      if (p is Map) {
        final m = p['morning'];
        final e = p['evening'];
        final hasSteps = (m is List && m.isNotEmpty) ||
            (e is List && e.isNotEmpty);
        if (hasSteps) {
          latest = r;
          break;
        }
      }
    }
    final today = DateTime.now();
    final dayUtc = DateTime.utc(today.year, today.month, today.day);
    final done = await completions.completedFor(userId: user.id, day: dayUtc);
    final streak = await completions.streak(user.id);

    return jsonResponse(200, {
      'date': dayUtc.toIso8601String(),
      'streak': streak,
      'has_routine': latest != null,
      'routine_id': latest?['id'],
      'morning': _stepsWithDone(latest, 'morning', done),
      'evening': _stepsWithDone(latest, 'evening', done),
    });
  }

  List<Map<String, dynamic>> _stepsWithDone(
      Map<String, dynamic>? routine, String phase, Set<String> done) {
    if (routine == null) return const [];
    final payload = routine['payload'];
    if (payload is! Map) return const [];
    final raw = payload[phase];
    if (raw is! List) return const [];
    return [
      for (var i = 0; i < raw.length; i++)
        {
          'index': i,
          'title': (raw[i] is Map) ? raw[i]['title'] : '$raw[i]',
          'ingredients': (raw[i] is Map)
              ? (raw[i]['ingredients'] as List? ?? const [])
              : const [],
          'explanation':
              (raw[i] is Map) ? (raw[i]['explanation'] ?? '') : '',
          'done': done.contains('$phase:$i'),
        }
    ];
  }

  Future<Response> _checkStep(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final phase = body['phase'] as String? ?? '';
    final index = (body['step_index'] as num?)?.toInt() ?? -1;
    if (!const {'morning', 'evening'}.contains(phase) || index < 0) {
      return jsonResponse(400, {'error': 'invalid_request'});
    }
    final today = DateTime.now();
    await completions.check(
      userId: user.id,
      day: DateTime.utc(today.year, today.month, today.day),
      phase: phase,
      stepIndex: index,
      stepTitle: body['step_title'] as String?,
    );
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _uncheckStep(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final phase = body['phase'] as String? ?? '';
    final index = (body['step_index'] as num?)?.toInt() ?? -1;
    if (!const {'morning', 'evening'}.contains(phase) || index < 0) {
      return jsonResponse(400, {'error': 'invalid_request'});
    }
    final today = DateTime.now();
    await completions.uncheck(
      userId: user.id,
      day: DateTime.utc(today.year, today.month, today.day),
      phase: phase,
      stepIndex: index,
    );
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _getSettings(Request req, UserRow user) async {
    final s = await users.getSettings(user.id);
    return jsonResponse(200, s);
  }

  Future<Response> _putSettings(Request req, UserRow user) async {
    final body = jsonDecode(await req.readAsString());
    if (body is! Map<String, dynamic>) {
      return jsonResponse(400, {'error': 'invalid_request'});
    }
    await users.setSettings(user.id, body);
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _export(Request req, UserRow user) async {
    final data = await users.exportData(user.id);
    return Response(
      200,
      body: jsonEncode(data),
      headers: {
        'content-type': 'application/json',
        'content-disposition':
            'attachment; filename="myskin-export.json"',
      },
    );
  }

  Future<Response> _deleteAccount(Request req, UserRow user) async {
    await users.deleteAccount(user.id);
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _progress(Request req, UserRow user) async {
    final days =
        int.tryParse(req.url.queryParameters['days'] ?? '') ?? 30;
    final cutoff =
        DateTime.now().toUtc().subtract(Duration(days: days.clamp(7, 365)));
    final all = await scans.listForUser(user.id, limit: 365);
    final inWindow =
        all.where((s) => s.createdAt.isAfter(cutoff)).toList();

    final points = inWindow
        .map((s) => {
              'id': s.id,
              'date': s.createdAt.toUtc().toIso8601String(),
              'score': s.score,
              'hydration': s.hydration,
              'sebum': s.sebum,
              'tone': s.tone,
              'pores': s.pores,
              'has_photo': s.hasPhoto,
            })
        .toList();

    final streak = await completions.streak(user.id);

    return jsonResponse(200, {
      'days': days,
      'points': points,
      'stats': {
        'scans_total': all.length,
        'scans_in_window': inWindow.length,
        'completion_streak': streak,
        'latest_score':
            inWindow.isNotEmpty ? inWindow.first.score : null,
        'first_score':
            inWindow.isNotEmpty ? inWindow.last.score : null,
      },
    });
  }

  Future<Response> _getChat(Request req, UserRow user) async {
    final items = await chatMessages.listForUser(user.id);
    return jsonResponse(200, {'items': items});
  }

  Future<Response> _clearChat(Request req, UserRow user) async {
    await chatMessages.clear(user.id);
    return jsonResponse(200, {'ok': true});
  }
}

/// CORS middleware that supports either a wildcard `*` (dev) or a strict
/// origin whitelist (prod). For prod set `CORS_ALLOWED_ORIGINS=https://a,https://b`.
Middleware corsMiddleware({required List<String> allowedOrigins}) {
  final allowAny = allowedOrigins.contains('*') || allowedOrigins.isEmpty;
  return (inner) => (req) async {
        final origin = req.headers['origin'];
        final allow = allowAny
            ? '*'
            : (origin != null && allowedOrigins.contains(origin)
                ? origin
                : null);
        final headers = <String, String>{
          if (allow != null) 'access-control-allow-origin': allow,
          'access-control-allow-methods':
              'GET,POST,PUT,PATCH,DELETE,OPTIONS',
          'access-control-allow-headers': 'content-type,authorization',
          if (!allowAny) 'vary': 'Origin',
        };
        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: headers);
        }
        final resp = await inner(req);
        return resp.change(headers: {...resp.headers, ...headers});
      };
}

/// Sliding-window rate limiter — keyed by IP for /auth/send-code.
/// In-memory; acceptable for single-instance deploys. For multi-instance
/// switch to Redis.
class RateLimiter {
  RateLimiter({this.maxPerMinute = 3, this.maxPerHour = 20});

  final int maxPerMinute;
  final int maxPerHour;
  final Map<String, List<DateTime>> _hits = {};

  Duration? denyFor(String key) {
    final now = DateTime.now();
    final list = _hits[key] ??= <DateTime>[];
    list.removeWhere(
        (t) => t.isBefore(now.subtract(const Duration(hours: 1))));
    final lastMinute = list
        .where((t) => t.isAfter(now.subtract(const Duration(minutes: 1))))
        .length;
    if (lastMinute >= maxPerMinute) return const Duration(minutes: 1);
    if (list.length >= maxPerHour) return const Duration(hours: 1);
    list.add(now);
    return null;
  }
}

/// Public read of legal documents (privacy policy, terms, consent).
/// Content is stored in app_settings under fixed keys; admin can edit it from
/// the admin panel without redeploying. No auth — anybody can read the legal
/// documents of an app they're considering signing up to.
class LegalHandlers {
  LegalHandlers({required this.appSettings});

  final AppSettingsRepository appSettings;

  static const _allowed = {'legal_terms', 'legal_privacy', 'legal_consent'};

  Router router() => Router()..get('/legal/<key>', _get);

  Future<Response> _get(Request req) async {
    final key = req.params['key']!;
    if (!_allowed.contains(key)) {
      return jsonResponse(404, {'error': 'unknown_legal_key'});
    }
    final value = await appSettings.get(key);
    return jsonResponse(200, {
      'key': key,
      'markdown': value ?? '',
    });
  }
}

class NotificationHandlers {
  NotificationHandlers({required this.sessions, required this.notifications});

  final SessionRepository sessions;
  final NotificationRepository notifications;

  Router router() => Router()
    ..get('/me/notifications', _withUser(_list))
    ..get('/me/notifications/unread_count', _withUser(_unreadCount))
    ..post('/me/notifications/read_all', _withUser(_markAllRead))
    ..post('/me/notifications/<id>/read', _withUser(_markRead));

  Handler _withUser(Future<Response> Function(Request, UserRow) inner) =>
      (Request req) async {
        final token = _bearer(req);
        if (token == null) return jsonResponse(401, {'error': 'unauthorized'});
        final user = await sessions.userForToken(token);
        if (user == null) return jsonResponse(401, {'error': 'unauthorized'});
        if (user.isBlocked) {
          return jsonResponse(403, {'error': 'user_blocked'});
        }
        return inner(req, user);
      };

  Future<Response> _list(Request req, UserRow user) async {
    final items = await notifications.listForUser(user.id);
    final unread = await notifications.unreadCount(user.id);
    return jsonResponse(200, {'items': items, 'unread_count': unread});
  }

  Future<Response> _unreadCount(Request req, UserRow user) async {
    final n = await notifications.unreadCount(user.id);
    return jsonResponse(200, {'unread_count': n});
  }

  Future<Response> _markRead(Request req, UserRow user) async {
    final id = req.params['id']!;
    final ok = await notifications.markRead(userId: user.id, id: id);
    if (!ok) return jsonResponse(404, {'error': 'not_found_or_already_read'});
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _markAllRead(Request req, UserRow user) async {
    final n = await notifications.markAllRead(user.id);
    return jsonResponse(200, {'updated': n});
  }
}

Middleware rateLimitMiddleware({
  required RateLimiter limiter,
  required Set<String> protectedPaths,
}) {
  return (inner) => (req) async {
        if (!protectedPaths.contains(req.url.path)) return inner(req);
        final ip = req.headers['x-forwarded-for']?.split(',').first.trim() ??
            req.headers['x-real-ip'] ??
            'unknown';
        final cooldown = limiter.denyFor(ip);
        if (cooldown != null) {
          return jsonResponse(429, {
            'error': 'too_many_requests',
            'retry_after_sec': cooldown.inSeconds,
          });
        }
        return inner(req);
      };
}
