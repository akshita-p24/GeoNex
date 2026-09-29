import 'package:flutter/material.dart';
import '../features/auth/login_screen.dart';
import '../features/shell/main_shell.dart';
import '../state/app_state.dart';
import '../core/services/auth_service.dart';
import '../backend/http_backend_client.dart';
import 'theme.dart';

class RiskToActionApp extends StatefulWidget {
  const RiskToActionApp({super.key});

  @override
  State<RiskToActionApp> createState() => _RiskToActionAppState();
}

class _RiskToActionAppState extends State<RiskToActionApp> {
  late final AuthService _authService;
  late final AppState _appState;
  bool _authChecked = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _authService.addListener(_onAuthChange);
    // Use real HTTP client backed by auth service.
    _appState = AppState(
      backendClient: HttpBackendClient(authService: _authService),
    );
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    if (mounted) setState(() {});
  }

  void _handleLogout() {
    _authService.logout();
    // Reset app state data after logout.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = _authService.isAuthenticated;

    return MaterialApp(
      title: 'Terra Sense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: isAuthenticated
          ? MainShell(
              appState: _appState,
              onLogout: _handleLogout,
            )
          : LoginScreen(
              appState: _appState,
              authService: _authService,
              onLoginSuccess: () {
                // Sync the user profile into AppState after login.
                final user = _authService.currentUser;
                if (user != null) {
                  _appState.setAuthenticatedUser(user);
                }
                setState(() {});
              },
            ),
    );
  }
}
