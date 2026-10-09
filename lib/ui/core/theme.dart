import 'package:flutter/material.dart';

const ink = Color(0xFF141414);
const panel = Color(0xFF262626);
const brandRed = Color(0xFFE50914);
const muted = Color(0xFFB3B3B3);

ThemeData anikkuTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ink,
  colorScheme: ColorScheme.fromSeed(
    seedColor: brandRed,
    brightness: Brightness.dark,
    primary: brandRed,
    surface: panel,
    onSurface: Colors.white,
    onPrimary: Colors.white,
  ),
  textTheme: const TextTheme(
    displaySmall: TextStyle(
      fontSize: 42,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.5,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -.7,
    ),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 18, height: 1.5),
    bodyMedium: TextStyle(fontSize: 16, height: 1.4),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: panel,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: brandRed, width: 2),
      borderRadius: BorderRadius.circular(4),
    ),
  ),
);
