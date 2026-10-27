import 'package:flutter/material.dart';

import 'core/theme/app_tema.dart';
import 'features/camara/data/almacenamiento_repository.dart';
import 'features/camara/presentation/pages/camara_page.dart';

class CamaraRecursosApp extends StatelessWidget {
  const CamaraRecursosApp({super.key, required this.repositorio});

  final AlmacenamientoRepository repositorio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cámara y Recursos',
      debugShowCheckedModeBanner: false,
      theme: AppTema.claro,
      home: CamaraPage(repositorio: repositorio),
    );
  }
}
