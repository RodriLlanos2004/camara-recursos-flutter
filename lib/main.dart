import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'features/camara/data/almacenamiento_repository.dart';

Future<void> main() async {
  // Necesario antes de usar plugins (path_provider) fuera de runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Vertical fija: evita reconstruir la vista previa y reorientar la
  // textura de la cámara en cada giro del teléfono.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Una sola instancia del repositorio, inyectada por constructor.
  final repositorio = AlmacenamientoRepository();

  // RF-03 (red de seguridad): el SO puede matar la app sin entregar el estado
  // `detached`, así que la limpieza de cierre no está garantizada. Limpiar
  // también al arrancar asegura que nunca se acumule basura entre sesiones.
  await repositorio.limpiarTemporales();

  runApp(CamaraRecursosApp(repositorio: repositorio));
}
