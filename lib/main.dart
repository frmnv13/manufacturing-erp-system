import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/app_state_store.dart';
import 'data/local_database.dart';
import 'data/remote_auth_api.dart';
import 'models/auth_models.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppStateStore.instance.init();
  } catch (_) {
    // Keep app running with in-memory state when local DB is unavailable.
  }
  runApp(const KeuanganKampusApp());
}

class KeuanganKampusApp extends StatelessWidget {
  const KeuanganKampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistem Keuangan Kampus',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const AppRootScreen(),
    );
  }

  ThemeData _buildTheme() {
    const seedColor = Color(0xFF2563EB);
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

class AppRootScreen extends StatefulWidget {
  const AppRootScreen({super.key});

  @override
  State<AppRootScreen> createState() => _AppRootScreenState();
}

class _AppRootScreenState extends State<AppRootScreen> {
  final RemoteAuthApi _authApi = RemoteAuthApi.fromEnvironment();
  AuthSession? _session;
  bool _isBootstrapping = true;

  @override
  void initState() {
    super.initState();
    _bootstrapAuthState();
  }

  Future<void> _bootstrapAuthState() async {
    if (!_authApi.isConfigured) {
      AppStateStore.instance.setRemoteSessionToken(null);
      if (!mounted) {
        return;
      }
      setState(() {
        _isBootstrapping = false;
      });
      return;
    }

    try {
      final saved = await LocalDatabase.instance.loadAuthSession();
      if (saved == null) {
        AppStateStore.instance.setRemoteSessionToken(null);
        if (!mounted) {
          return;
        }
        setState(() {
          _session = null;
          _isBootstrapping = false;
        });
        return;
      }

      final savedSession = AuthSession.fromMap(saved);
      if (savedSession.token.trim().isEmpty) {
        await LocalDatabase.instance.clearAuthSession();
        AppStateStore.instance.setRemoteSessionToken(null);
        if (!mounted) {
          return;
        }
        setState(() {
          _session = null;
          _isBootstrapping = false;
        });
        return;
      }

      if (savedSession.expiresAt != null &&
          savedSession.expiresAt!.isBefore(DateTime.now())) {
        await LocalDatabase.instance.clearAuthSession();
        AppStateStore.instance.setRemoteSessionToken(null);
        if (!mounted) {
          return;
        }
        setState(() {
          _session = null;
          _isBootstrapping = false;
        });
        return;
      }

      final user = await _authApi.me(savedSession.token);
      final activeSession = AuthSession(
        token: savedSession.token,
        tokenType: savedSession.tokenType,
        expiresAt: savedSession.expiresAt,
        user: user,
      );

      await LocalDatabase.instance.saveAuthSession(activeSession.toMap());
      AppStateStore.instance.setRemoteSessionToken(activeSession.token);

      if (!mounted) {
        return;
      }
      setState(() {
        _session = activeSession;
        _isBootstrapping = false;
      });
    } catch (_) {
      await LocalDatabase.instance.clearAuthSession();
      AppStateStore.instance.setRemoteSessionToken(null);
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _isBootstrapping = false;
      });
    }
  }

  Future<void> _handleLogin(LoginSubmission submission) async {
    try {
      final session = await _authApi.login(
        username: submission.username,
        password: submission.password,
        officeCode: submission.officeCode,
      );

      await LocalDatabase.instance.saveAuthSession(session.toMap());
      AppStateStore.instance.setRemoteSessionToken(session.token);

      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final current = _session;
    if (current == null) {
      return;
    }

    try {
      await _authApi.logout(current.token);
    } catch (_) {
      // Keep local logout path even if API request fails.
    }

    await LocalDatabase.instance.clearAuthSession();
    AppStateStore.instance.setRemoteSessionToken(null);

    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_authApi.isConfigured) {
      return const DashboardScreen();
    }

    if (_session == null) {
      return LoginScreen(onSubmit: _handleLogin);
    }

    return DashboardScreen(
      onLogoutRequested: _handleLogout,
      signedInUsername: _session!.user.username,
      signedInRole: _session!.user.role,
      signedInToken: _session!.token,
    );
  }
}
