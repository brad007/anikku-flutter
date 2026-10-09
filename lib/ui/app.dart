import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/library_model.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';

class AnikkuApp extends StatelessWidget {
  const AnikkuApp({super.key, required this.model});
  final LibraryModel model;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Anikku',
    debugShowCheckedModeBanner: false,
    theme: anikkuTheme(),
    shortcuts: {
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
    },
    home: HomeScreen(model: model),
  );
}
