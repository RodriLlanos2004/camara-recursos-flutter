import 'package:path/path.dart' as p;

enum TipoMedio { foto, video }

/// Archivo recién capturado que todavía vive en el directorio TEMPORAL.
///
/// Solo pasa al directorio persistente si el usuario lo confirma (RF-04).
/// Mientras tanto se considera basura potencial que debe limpiarse (RF-03).
class MedioCapturado {
  const MedioCapturado({
    required this.rutaTemporal,
    required this.tipo,
    this.duracion,
  });

  final String rutaTemporal;
  final TipoMedio tipo;

  /// Solo para videos: duración medida durante la grabación.
  final Duration? duracion;

  bool get esVideo => tipo == TipoMedio.video;

  /// Extensión original (`.jpg`, `.mp4`...). Se conserva al renombrar para
  /// que el sistema operativo siga sabiendo qué tipo de archivo es.
  String get extension {
    final ext = p.extension(rutaTemporal).toLowerCase();
    if (ext.isNotEmpty) return ext;
    return esVideo ? '.mp4' : '.jpg';
  }
}
