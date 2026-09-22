import 'package:flutter/material.dart';
import '../features/auth/login_screen.dart';
import '../features/shell/main_shell.dart';
import '../state/app_state.dart';
import 'theme.dart';

class RiskToActionApp extends StatefulWidget {
  const RiskToActionApp({super.key});
  @override
  State<RiskToActionApp> createState() => _RiskToActionAppState();
}
class _RiskToActionAppState extends State<RiskToActionApp> {
  late final AppState _appState;
  bool _isAuthenticated = true; // Defaults to authenticated demo mode
  @override
  void initState() {
    super.initState();
    _appState = AppState();
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terra Sense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _isAuthenticated
          ? MainShell(
              appState: _appState,
              onLogout: () => setState(() => _isAuthenticated = false),
            )
          : LoginScreen(
              appState: _appState,
              onLoginSuccess: () => setState(() => _isAuthenticated = true),
            ),
    );
  }
}
