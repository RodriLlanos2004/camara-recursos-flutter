import 'package:path/path.dart' as p;

import 'medio_capturado.dart';

/// Archivo ya confirmado que vive en el directorio PERSISTENTE (documents).
class ElementoGaleria {
  const ElementoGaleria({
    required this.ruta,
    required this.tipo,
    required this.tamanoBytes,
    required this.modificado,
  });

  final String ruta;
  final TipoMedio tipo;
  final int tamanoBytes;
  final DateTime modificado;

  String get nombre => p.basename(ruta);
}

/// Fotografía del uso de almacenamiento, para demostrar la limpieza (RF-03).
class ResumenAlmacenamiento {
  const ResumenAlmacenamiento({
    required this.archivosTemporales,
    required this.bytesTemporales,
    required this.archivosGaleria,
    required this.bytesGaleria,
  });

  final int archivosTemporales;
  final int bytesTemporales;
  final int archivosGaleria;
  final int bytesGaleria;
}
