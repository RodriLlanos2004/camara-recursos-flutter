/// Reglas para el nombre personalizado que el usuario escribe (RF-02).
///
/// Lógica pura, sin Flutter ni sistema de archivos: por eso se puede
/// probar con pruebas unitarias (ver test/widget_test.dart).
class NombreArchivo {
  const NombreArchivo._();

  static const int longitudMaxima = 60;

  /// Letras (incluidas acentuadas y ñ), dígitos, espacio, guion y guion bajo.
  /// Se excluyen `/ \ : * ? " < > |` y el punto: son separadores de ruta,
  /// caracteres prohibidos en algunos sistemas o permitirían cambiar la
  /// extensión del archivo.
  static final RegExp _permitidos = RegExp(r'^[A-Za-z0-9 _\-áéíóúÁÉÍÓÚñÑüÜ]+$');

  /// Contrato de TextFormField.validator: `null` significa válido.
  static String? validar(String? valor) {
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Escribe un nombre para el archivo.';
    if (texto.length > longitudMaxima) {
      return 'Máximo $longitudMaxima caracteres.';
    }
    if (!_permitidos.hasMatch(texto)) {
      return 'Usa solo letras, números, espacios, guiones y guiones bajos.';
    }
    return null;
  }

  /// Nombre final en disco: sin espacios al inicio/fin y con los espacios
  /// internos convertidos en guion bajo (`Mi viaje` → `Mi_viaje`).
  static String normalizar(String valor) =>
      valor.trim().replaceAll(RegExp(r'\s+'), '_');
}
