import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:dotenv/dotenv.dart';
import 'package:myskin_backend/db.dart';
import 'package:myskin_backend/repos.dart';

/// Seeds (or updates) the admin user from .env values.
/// Run: `dart run bin/seed_admin.dart`
Future<void> main(List<String> args) async {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final dbUrl = env['DATABASE_URL'];
  final login = env['ADMIN_LOGIN'];
  final password = env['ADMIN_PASSWORD'];
  if (dbUrl == null || login == null || password == null ||
      dbUrl.isEmpty || login.isEmpty || password.isEmpty) {
    stderr.writeln(
        'Set DATABASE_URL, ADMIN_LOGIN, ADMIN_PASSWORD in backend/.env');
    exit(1);
  }
  final pool = await openPool(dbUrl);
  await Migrator(pool).run();
  final admins = AdminRepository(pool);
  final hash = BCrypt.hashpw(password, BCrypt.gensalt());
  await admins.upsert(login: login, passwordHash: hash);
  stdout.writeln('Admin "$login" upserted.');
  await pool.close();
}
