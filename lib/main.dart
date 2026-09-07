import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'navigation/main_navigation_wrapper.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
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

  /// Non-critical initialization deferred until after the first frame renders.
  void _deferredInit() {
    // Pre-cache primary brand assets so they are decoded in GPU memory before navigation
    if (mounted) {
      precacheImage(const AssetImage('assets/logo/talentloq_horizontal_logo_transparent.png'), context);
      precacheImage(const AssetImage('assets/logo/talentloq_horizontal_logo.png'), context);
      precacheImage(const AssetImage('assets/logo/talentloq_icon_only.png'), context);
    }
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
