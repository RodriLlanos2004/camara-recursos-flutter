/// Utilidades de formato compartidas por todas las pantallas.
library;

String _dos(int n) => n.toString().padLeft(2, '0');

/// `75 s` → `01:15` · `3723 s` → `1:02:03`
String formatearDuracion(Duration duracion) {
  final horas = duracion.inHours;
  final minutos = _dos(duracion.inMinutes.remainder(60));
  final segundos = _dos(duracion.inSeconds.remainder(60));
  return horas > 0 ? '$horas:$minutos:$segundos' : '$minutos:$segundos';
}

/// `1536` → `1.5 KB` · `5242880` → `5.0 MB`
String formatearBytes(int bytes) {
  const unidades = ['B', 'KB', 'MB', 'GB'];
  var valor = bytes.toDouble();
  var indice = 0;
  while (valor >= 1024 && indice < unidades.length - 1) {
    valor /= 1024;
    indice++;
  }
  return indice == 0 ? '$bytes B' : '${valor.toStringAsFixed(1)} ${unidades[indice]}';
}

/// `27/10/2026 15:30`
String formatearFecha(DateTime fecha) =>
    '${_dos(fecha.day)}/${_dos(fecha.month)}/${fecha.year} '
    '${_dos(fecha.hour)}:${_dos(fecha.minute)}';

/// Marca de tiempo apta para nombres de archivo: `20261027_153012`
String marcaDeTiempo(DateTime fecha) =>
    '${fecha.year}${_dos(fecha.month)}${_dos(fecha.day)}_'
    '${_dos(fecha.hour)}${_dos(fecha.minute)}${_dos(fecha.second)}';
