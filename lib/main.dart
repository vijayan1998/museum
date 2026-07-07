import 'package:flutter/material.dart';
import 'package:museum/homescreen.dart';

/// Neumorphic dark music player — "Afterglow"
/// Recreates the center panel of the smart-home dashboard reference.
///
/// Add to pubspec.yaml (optional, for closer font match):
///   google_fonts: ^6.2.1
/// The code below uses default fonts with letter-spacing so it runs
/// without any extra packages.

void main() => runApp(const MusicPlayerApp());

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
class AppColors {
  static const bg = Color(0xFF23232B); // page background
  static const cardTop = Color(0xFF34313E); // player card gradient top
  static const cardBottom = Color(0xFF2A2731); // player card gradient bottom
  static const knob = Color(0xFF2E2733); // center dial fill
  static const cyan = Color(0xFF35E0E8); // accent cyan
  static const purple = Color(0xFF8A4FCF); // accent purple (arc glow)
  static const textPrimary = Color(0xFFEDEAF2);
  static const textDim = Color(0xFF8B8794);
  static const shadowDark = Color(0xFF17161C);
  static const shadowLight = Color(0x1AFFFFFF);
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const Scaffold(backgroundColor: AppColors.bg, body: HomeScreen()),
    );
  }
}
