// Pruebas unitarias de la lógica pura (no requieren cámara ni dispositivo).
// Ejecutar con: flutter test

import 'package:camara_recursos/core/utils/formato.dart';
import 'package:camara_recursos/features/camara/domain/medio_capturado.dart';
import 'package:camara_recursos/features/camara/domain/nombre_archivo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NombreArchivo.validar', () {
    test('acepta letras, acentos, números, espacios y guiones', () {
      expect(NombreArchivo.validar('Viaje a Mérida-2026'), isNull);
      expect(NombreArchivo.validar('foto_ñandú_01'), isNull);
    });

    test('rechaza vacío o solo espacios', () {
      expect(NombreArchivo.validar(''), isNotNull);
      expect(NombreArchivo.validar('   '), isNotNull);
      expect(NombreArchivo.validar(null), isNotNull);
    });

    test('rechaza separadores de ruta y puntos', () {
      expect(NombreArchivo.validar('../secreto'), isNotNull);
      expect(NombreArchivo.validar('carpeta/foto'), isNotNull);
      expect(NombreArchivo.validar('foto.png'), isNotNull);
    });

    test('rechaza nombres demasiado largos', () {
      expect(NombreArchivo.validar('a' * NombreArchivo.longitudMaxima), isNull);
      expect(NombreArchivo.validar('a' * (NombreArchivo.longitudMaxima + 1)), isNotNull);
    });
  });

  test('NombreArchivo.normalizar convierte espacios en guion bajo', () {
    expect(NombreArchivo.normalizar('  Mi   viaje  '), 'Mi_viaje');
  });

  group('MedioCapturado.extension', () {
    test('conserva la extensión original en minúsculas', () {
      const medio = MedioCapturado(rutaTemporal: '/tmp/CAP123.JPG', tipo: TipoMedio.foto);
      expect(medio.extension, '.jpg');
    });

    test('usa una extensión por defecto si el archivo no tiene', () {
      const video = MedioCapturado(rutaTemporal: '/tmp/REC123', tipo: TipoMedio.video);
      expect(video.extension, '.mp4');
    });
  });

  group('formato', () {
    test('formatearDuracion', () {
      expect(formatearDuracion(const Duration(seconds: 75)), '01:15');
      expect(formatearDuracion(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('formatearBytes', () {
      expect(formatearBytes(512), '512 B');
      expect(formatearBytes(1536), '1.5 KB');
      expect(formatearBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('marcaDeTiempo', () {
      expect(marcaDeTiempo(DateTime(2026, 10, 27, 9, 5, 3)), '20261027_090503');
    });
  });
}
