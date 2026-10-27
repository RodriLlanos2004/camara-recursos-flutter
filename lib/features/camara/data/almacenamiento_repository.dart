import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/elemento_galeria.dart';
import '../domain/medio_capturado.dart';
import '../domain/nombre_archivo.dart';

class ArchivoDuplicadoException implements Exception {
  const ArchivoDuplicadoException(this.nombre);

  final String nombre;

  @override
  String toString() => 'Ya existe "$nombre" en la galería.';
}

/// Única puerta de la app al sistema de archivos.
///
/// Distingue dos zonas con propósitos opuestos:
///
/// | Zona        | API                                  | Contenido                         |
/// |-------------|--------------------------------------|-----------------------------------|
/// | Temporal    | `getTemporaryDirectory()`            | Capturas sin confirmar. El SO puede borrarla cuando falta espacio. |
/// | Persistente | `getApplicationDocumentsDirectory()` | Capturas aceptadas. Sobrevive a reinicios y solo se borra al desinstalar. |
class AlmacenamientoRepository {
  static const String _carpetaGaleria = 'capturas';

  /// Extensiones que produce el plugin camera. La limpieza solo borra estos
  /// archivos: el directorio temporal también lo usan el motor de Flutter y
  /// otros plugins, y vaciarlo por completo podría romperlos.
  static const Set<String> _extensionesMultimedia = {
    '.jpg', '.jpeg', '.png', '.heic', '.mp4', '.mov', '.3gp', '.temp',
  };
  static const Set<String> _extensionesVideo = {'.mp4', '.mov', '.3gp'};

  // ---------------------------------------------------------------------------
  // Zona persistente (RF-04)
  // ---------------------------------------------------------------------------
  Future<Directory> directorioGaleria() async {
    final documentos = await getApplicationDocumentsDirectory();
    final galeria = Directory(p.join(documentos.path, _carpetaGaleria));
    if (!await galeria.exists()) await galeria.create(recursive: true);
    return galeria;
  }

  Future<String> _rutaDestino(String nombreElegido, String extension) async {
    final galeria = await directorioGaleria();
    return p.join(galeria.path, '${NombreArchivo.normalizar(nombreElegido)}$extension');
  }

  Future<bool> existeEnGaleria(String nombreElegido, String extension) async =>
      File(await _rutaDestino(nombreElegido, extension)).exists();

  /// Mueve el archivo temporal a la galería con el nombre del usuario.
  ///
  /// `rename` es un movimiento instantáneo (solo cambia la entrada del
  /// directorio, no copia bytes) cuando origen y destino están en el mismo
  /// sistema de archivos, que es lo normal en Android e iOS. Si el SO no lo
  /// permite, se copia y se borra el original: nunca quedan dos copias.
  Future<File> guardarEnGaleria(MedioCapturado medio, String nombreElegido) async {
    final origen = File(medio.rutaTemporal);
    if (!await origen.exists()) {
      throw FileSystemException('El archivo temporal ya no existe', medio.rutaTemporal);
    }

    final destino = await _rutaDestino(nombreElegido, medio.extension);
    if (await File(destino).exists()) {
      throw ArchivoDuplicadoException(p.basename(destino));
    }

    File guardado;
    try {
      guardado = await origen.rename(destino);
    } on FileSystemException {
      guardado = await origen.copy(destino);
      await origen.delete();
    }
    debugPrint('[Almacenamiento] Guardado en documentos: ${guardado.path}');
    return guardado;
  }

  Future<List<ElementoGaleria>> listarGaleria() async {
    final galeria = await directorioGaleria();
    final elementos = <ElementoGaleria>[];

    await for (final entidad in galeria.list(followLinks: false)) {
      if (entidad is! File) continue;
      final info = await entidad.stat();
      final extension = p.extension(entidad.path).toLowerCase();
      elementos.add(ElementoGaleria(
        ruta: entidad.path,
        tipo: _extensionesVideo.contains(extension) ? TipoMedio.video : TipoMedio.foto,
        tamanoBytes: info.size,
        modificado: info.modified,
      ));
    }

    elementos.sort((a, b) => b.modificado.compareTo(a.modificado));
    return elementos;
  }

  Future<void> eliminarDeGaleria(ElementoGaleria elemento) async {
    final archivo = File(elemento.ruta);
    if (await archivo.exists()) await archivo.delete();
  }

  // ---------------------------------------------------------------------------
  // Zona temporal (RF-03)
  // ---------------------------------------------------------------------------

  /// Borra de inmediato una captura descartada. Es idempotente: si ya no
  /// existe, no hace nada (la pantalla de confirmación y la de cámara pueden
  /// llamarla ambas sin error).
  Future<void> descartarTemporal(String ruta) async {
    try {
      final archivo = File(ruta);
      if (await archivo.exists()) {
        await archivo.delete();
        debugPrint('[Temporales] Descartado: ${p.basename(ruta)}');
      }
    } on FileSystemException catch (e) {
      debugPrint('[Temporales] No se pudo borrar $ruta: ${e.message}');
    }
  }

  /// Escanea el directorio temporal y borra toda captura multimedia.
  /// Devuelve cuántos archivos se eliminaron.
  Future<int> limpiarTemporales() async {
    final temporal = await getTemporaryDirectory();
    if (!await temporal.exists()) return 0;

    // Primero se recolecta y después se borra: modificar un directorio
    // mientras se recorre su listado puede saltarse entradas.
    final candidatos = await _archivosMultimedia(temporal);

    var borrados = 0;
    for (final archivo in candidatos) {
      try {
        await archivo.delete();
        borrados++;
      } on FileSystemException catch (e) {
        debugPrint('[Temporales] No se pudo borrar ${archivo.path}: ${e.message}');
      }
    }
    debugPrint('[Temporales] Limpieza completa: $borrados archivo(s) eliminado(s)');
    return borrados;
  }

  Future<ResumenAlmacenamiento> resumen() async {
    final temporales = await _archivosMultimedia(await getTemporaryDirectory());
    final galeria = await listarGaleria();

    var bytesTemporales = 0;
    for (final archivo in temporales) {
      try {
        bytesTemporales += await archivo.length();
      } on FileSystemException {
        // Pudo borrarse entre el listado y la lectura: se ignora.
      }
    }

    return ResumenAlmacenamiento(
      archivosTemporales: temporales.length,
      bytesTemporales: bytesTemporales,
      archivosGaleria: galeria.length,
      bytesGaleria: galeria.fold<int>(0, (total, e) => total + e.tamanoBytes),
    );
  }

  Future<List<File>> _archivosMultimedia(Directory directorio) async {
    if (!await directorio.exists()) return const [];
    final archivos = <File>[];
    await for (final entidad in directorio.list(recursive: true, followLinks: false)) {
      if (entidad is File &&
          _extensionesMultimedia.contains(p.extension(entidad.path).toLowerCase())) {
        archivos.add(entidad);
      }
    }
    return archivos;
  }
}
