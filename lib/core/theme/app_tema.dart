import 'package:flutter/material.dart';

/// Tema único de la aplicación.
class AppTema {
  const AppTema._();

  static const Color colorGrabacion = Color(0xFFE53935);

  static ThemeData get claro => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3949AB)),
        useMaterial3: true,
      );
}
