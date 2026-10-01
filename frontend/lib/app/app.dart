import 'package:flutter/material.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
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
  bool _showSignUp = false;
  bool _isCheckingAuth = true;
  String? _prefilledEmail;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _authService.addListener(_onAuthChange);
    // Use real HTTP client backed by auth service
    _appState = AppState(
      backendClient: HttpBackendClient(authService: _authService),
    );
    _checkInitialAuth();
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  Future<void> _checkInitialAuth() async {
    final restored = await _authService.restoreSavedSession();
    if (restored && _authService.currentUser != null) {
      _appState.setAuthenticatedUser(_authService.currentUser!);
      _appState.loadAllData();
    }
    if (mounted) {
      setState(() => _isCheckingAuth = false);
    }
  }

  void _onAuthChange() {
    if (mounted) setState(() {});
  }

  void _handleLogout() {
    _authService.logout();
    _showSignUp = false;
    _prefilledEmail = null;
    setState(() {});
  }

  void _onAuthSuccess() {
    final user = _authService.currentUser;
    if (user != null) {
      _appState.setAuthenticatedUser(user);
      _appState.loadAllData();
    }
    _showSignUp = false;
    setState(() {});
  }

  void _onSignUpCompleted(String email) {
    setState(() {
      _prefilledEmail = email;
      _showSignUp = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth) {
      return MaterialApp(
        title: 'Terra Sense',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) {
        final isAuthenticated = _authService.isAuthenticated;
        final localeTag = _appState.selectedLocale;

        return MaterialApp(
          title: 'Terra Sense',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
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
              : _showSignUp
                  ? SignUpScreen(
                      appState: _appState,
                      authService: _authService,
                      onSignUpSuccess: _onSignUpCompleted,
                      onNavigateToLogin: () =>
                          setState(() => _showSignUp = false),
                    )
                  : LoginScreen(
                      appState: _appState,
                      authService: _authService,
                      initialEmail: _prefilledEmail,
                      onLoginSuccess: _onAuthSuccess,
                      onNavigateToSignUp: () =>
                          setState(() => _showSignUp = true),
                    ),
        );
      },
    );
  }
}
