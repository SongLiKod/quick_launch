import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'services/settings_service.dart';

/// 全局导航键，用于在 main 中无 context 时弹出对话框
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class QuickLaunchApp extends StatefulWidget {
  const QuickLaunchApp({super.key});

  @override
  State<QuickLaunchApp> createState() => _QuickLaunchAppState();
}

class _QuickLaunchAppState extends State<QuickLaunchApp> {
  @override
  void initState() {
    super.initState();
    SettingsService().themeMode.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SettingsService().themeMode.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = SettingsService().themeMode.value;
    return MaterialApp(
      title: '快速启动',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}
