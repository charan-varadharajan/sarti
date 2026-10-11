import 'package:flutter/material.dart';
import 'package:sarti_mobile/src/features/foundation/foundation_screen.dart';

class SartiApp extends StatelessWidget {
  const SartiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sarti',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF386A20),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const FoundationScreen(),
    );
  }
}
