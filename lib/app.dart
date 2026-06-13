import 'package:flutter/material.dart';
import 'pages/home_page.dart';

class QuickLaunchApp extends StatelessWidget {
  const QuickLaunchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '快速启动',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const HomePage(),
    );
  }
}
