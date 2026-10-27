/// Modo activo de la pantalla de cámara (RF-01: captura dual).
enum ModoCaptura {
  foto('Foto'),
  video('Video');

  const ModoCaptura(this.etiqueta);

  final String etiqueta;
}
