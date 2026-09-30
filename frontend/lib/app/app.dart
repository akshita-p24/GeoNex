import 'package:flutter/material.dart';
import '../features/auth/login_screen.dart';
import '../features/shell/main_shell.dart';
import '../localization/app_localizations.dart';
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
    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) {
        final isAuthenticated = _authService.isAuthenticated;
        final localeTag = _appState.selectedLocale;

        return MaterialApp(
          title: 'Terra Sense',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          // Locale changes when user picks a language in Settings.
          locale: Locale(localeTag),
          supportedLocales: const [
            Locale('en'),
            Locale('hi'),
            Locale('as'),
            Locale('bn'),
            Locale('ne'),
            Locale('brx'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
          ],

          home: isAuthenticated
              ? MainShell(
                  appState: _appState,
                  onLogout: _handleLogout,
                )
              : LoginScreen(
                  appState: _appState,
                  authService: _authService,
                  onLoginSuccess: () {
                    final user = _authService.currentUser;
                    if (user != null) {
                      _appState.setAuthenticatedUser(user);
                      _appState.loadAllData();
                    }
                    setState(() {});
                  },
                ),
        );
      },
    );
  }
}
