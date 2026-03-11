import 'package:sembast/sembast.dart';

import 'db_opener_stub.dart'
    if (dart.library.io) 'db_opener_io.dart'
    if (dart.library.html) 'db_opener_web.dart';
import '../models/dashboard_state_model.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const _dbName = 'keuangan_kampus.db';
  static const _stateKey = 'dashboard_state';
  static const _authSessionKey = 'auth_session';

  final _store = stringMapStoreFactory.store('application_state');
  final _authStore = stringMapStoreFactory.store('auth_state');
  Database? _database;

  Future<void> init() async {
    if (_database != null) {
      return;
    }
    _database = await openLocalDatabase(_dbName);
  }

  Future<DashboardStateModel> loadDashboardState({
    required DashboardStateModel fallback,
  }) async {
    final db = await _ensureDb();
    final raw = await _store.record(_stateKey).get(db);
    if (raw == null) {
      return fallback;
    }

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      map[entry.key.toString()] = entry.value;
    }
    return DashboardStateModel.fromMap(map, fallback: fallback);
  }

  Future<void> saveDashboardState(DashboardStateModel state) async {
    final db = await _ensureDb();
    await _store.record(_stateKey).put(db, state.toMap());
  }

  Future<Map<String, Object?>?> loadAuthSession() async {
    final db = await _ensureDb();
    final raw = await _authStore.record(_authSessionKey).get(db);
    if (raw == null) {
      return null;
    }

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      map[entry.key.toString()] = entry.value;
    }
    return map;
  }

  Future<void> saveAuthSession(Map<String, Object?> sessionMap) async {
    final db = await _ensureDb();
    await _authStore.record(_authSessionKey).put(db, sessionMap);
  }

  Future<void> clearAuthSession() async {
    final db = await _ensureDb();
    await _authStore.record(_authSessionKey).delete(db);
  }

  Future<Database> _ensureDb() async {
    if (_database == null) {
      await init();
    }
    return _database!;
  }
}
