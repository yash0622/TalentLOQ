import 'package:flutter/material.dart';
import 'navigation/main_navigation_wrapper.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TalentLOQApp());
}

class TalentLOQApp extends StatefulWidget {
  const TalentLOQApp({super.key});

  @override
  State<TalentLOQApp> createState() => _TalentLOQAppState();
}

class _TalentLOQAppState extends State<TalentLOQApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme(ThemeMode newMode) {
    setState(() {
      _themeMode = newMode;
    });
  }

  @override
  void initState() {
    super.initState();
    // Defer non-critical initialization until after the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredInit();
    });
  }

  /// Non-critical initialization deferred until after the first frame.
  /// Add analytics SDKs, notification permission prompts, etc. here.
  void _deferredInit() {
    // Placeholder: analytics, push notification setup, etc.
    debugPrint('[STARTUP] Deferred initialization complete');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalentLOQ Modern Professional',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: MainNavigationWrapper(
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
