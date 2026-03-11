import '../models/dashboard_state_model.dart';
import 'local_database.dart';
import 'remote_state_api.dart';

class AppStateStore {
  AppStateStore._();

  static final AppStateStore instance = AppStateStore._();

  final LocalDatabase _localDatabase = LocalDatabase.instance;
  final RemoteStateApi _remoteApi = RemoteStateApi.fromEnvironment();

  void setRemoteSessionToken(String? token) {
    _remoteApi.setTokenOverride(token);
  }

  Future<void> init() async {
    await _localDatabase.init();
  }

  Future<DashboardStateModel> loadDashboardState({
    required DashboardStateModel fallback,
  }) async {
    DashboardStateModel localState;
    try {
      localState = await _localDatabase.loadDashboardState(
        fallback: fallback,
      );
    } catch (_) {
      localState = fallback;
    }

    if (!_remoteApi.isConfigured) {
      return localState;
    }

    try {
      final remoteStateMap = await _remoteApi.fetchState();
      if (remoteStateMap == null) {
        return localState;
      }
      final remoteState = DashboardStateModel.fromMap(
        remoteStateMap,
        fallback: localState,
      );
      await _localDatabase.saveDashboardState(remoteState);
      return remoteState;
    } catch (_) {
      return localState;
    }
  }

  Future<void> saveDashboardState(DashboardStateModel state) async {
    try {
      await _localDatabase.saveDashboardState(state);
    } catch (_) {
      // Keep remote sync attempt even if local write fails.
    }

    if (!_remoteApi.isConfigured) {
      return;
    }

    try {
      await _remoteApi.pushState(state.toMap());
    } catch (_) {
      // Keep local persistence as source of truth when remote is unavailable.
    }
  }
}
