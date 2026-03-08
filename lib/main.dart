import 'package:flutter/material.dart';
import 'views/screens/main_shell.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swaply',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D2B9F)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MainShell(),
    );
  }
}
