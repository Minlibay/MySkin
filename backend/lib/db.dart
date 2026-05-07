import 'dart:io';
import 'package:postgres/postgres.dart';

/// Parses postgres://user:pass@host:port/db into a v3 [Endpoint].
Endpoint parseDatabaseUrl(String url) {
  final uri = Uri.parse(url);
  final userInfo = uri.userInfo.split(':');
  return Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.path.replaceFirst('/', ''),
    username: userInfo.isNotEmpty ? Uri.decodeComponent(userInfo[0]) : null,
    password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : null,
  );
}

Future<Pool> openPool(String url) async {
  final endpoint = parseDatabaseUrl(url);
  final pool = Pool.withEndpoints(
    [endpoint],
    settings: const PoolSettings(
      maxConnectionCount: 10,
      sslMode: SslMode.disable,
    ),
  );
  // Probe — fail fast if DB is unreachable.
  await pool.execute('SELECT 1');
  return pool;
}

class Migrator {
  Migrator(this.pool, {this.directory = 'migrations'});
  final Pool pool;
  final String directory;

  Future<void> run() async {
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS _migrations (
        version TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      stderr.writeln('Migrations directory $directory not found.');
      return;
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final applied = await pool.execute('SELECT version FROM _migrations');
    final appliedSet = applied.map((r) => r[0] as String).toSet();

    for (final file in files) {
      final version = file.uri.pathSegments.last;
      if (appliedSet.contains(version)) continue;
      final sql = file.readAsStringSync();
      stdout.writeln('→ applying $version');
      await pool.runTx((tx) async {
        await tx.execute(sql, queryMode: QueryMode.simple);
        await tx.execute(
          Sql.named('INSERT INTO _migrations (version) VALUES (@v)'),
          parameters: {'v': version},
        );
      });
    }
    stdout.writeln('Migrations up to date.');
  }
}
