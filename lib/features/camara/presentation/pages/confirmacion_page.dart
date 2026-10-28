import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/formato.dart';
import '../../data/almacenamiento_repository.dart';
import '../../domain/medio_capturado.dart';
import '../../domain/nombre_archivo.dart';
import '../widgets/visor_video.dart';

/// RF-02: vista previa de la captura y nombre personalizado.
///
/// Devuelve `true` con Navigator.pop solo si el archivo se movió a la
/// galería. Cualquier otro resultado significa "descartado".
class ConfirmacionPage extends StatefulWidget {
  const ConfirmacionPage({
    super.key,
    required this.medio,
    required this.repositorio,
  });

  final MedioCapturado medio;
  final AlmacenamientoRepository repositorio;

  @override
  State<ConfirmacionPage> createState() => _ConfirmacionPageState();
}

class _ConfirmacionPageState extends State<ConfirmacionPage> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;

  VideoPlayerController? _video;
  ImageProvider? _imagen;

  String? _errorNombre; // nombre duplicado (no lo detecta el validator)
  String? _errorMedio;
  bool _procesando = false;

  MedioCapturado get _medio => widget.medio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final prefijo = _medio.esVideo ? 'video' : 'foto';
    _nombreCtrl = TextEditingController(text: '${prefijo}_${marcaDeTiempo(DateTime.now())}');
    if (_medio.esVideo) unawaited(_iniciarVideo());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Una foto de 12 MP decodificada ocupa ~48 MB de RAM (4 bytes por píxel).
    // ResizeImage la decodifica directamente al ancho de la pantalla, que es
    // lo único que se va a mostrar.
    if (!_medio.esVideo && _imagen == null) {
      final ancho = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
      _imagen = ResizeImage(FileImage(File(_medio.rutaTemporal)), width: ancho);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nombreCtrl.dispose();
    // RT-02: el reproductor se destruye al salir de la previsualización.
    final video = _video;
    _video = null;
    if (video != null) unawaited(video.dispose());
    // Saca el bitmap decodificado de la caché global de imágenes.
    final imagen = _imagen;
    if (imagen != null) unawaited(imagen.evict());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Si la app deja de verse, el video se pausa: no tiene sentido seguir
    // decodificando fotogramas que nadie ve.
    if (estado != AppLifecycleState.resumed) unawaited(_video?.pause());
  }

  // ---------------------------------------------------------------------------
  // Video
  // ---------------------------------------------------------------------------
  Future<void> _iniciarVideo() async {
    final controlador = VideoPlayerController.file(File(_medio.rutaTemporal));
    _video = controlador;
    try {
      await controlador.initialize();
      if (!mounted || _video != controlador) return; // la pantalla ya se cerró
      await controlador.setLooping(true);
      await controlador.play();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMedio = 'No se pudo reproducir el video: $e');
    }
  }

  /// Suelta el archivo antes de moverlo: el reproductor lo mantiene abierto.
  Future<void> _liberarVideo() async {
    final video = _video;
    if (video == null) return;
    setState(() => _video = null);
    await video.dispose();
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------
  Future<void> _cancelar() async {
    setState(() => _procesando = true);
    await _liberarVideo();
    // RF-03: el archivo descartado se borra en el acto.
    await widget.repositorio.descartarTemporal(_medio.rutaTemporal);
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _aceptar() async {
    setState(() => _errorNombre = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final nombre = _nombreCtrl.text;
    if (await widget.repositorio.existeEnGaleria(nombre, _medio.extension)) {
      if (!mounted) return;
      setState(() => _errorNombre = 'Ya existe un archivo con ese nombre en la galería.');
      return;
    }

    setState(() => _procesando = true);
    try {
      await _liberarVideo();
      // RF-04: solo aquí el archivo sale de la zona temporal.
      await widget.repositorio.guardarEnGaleria(_medio, nombre);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArchivoDuplicadoException catch (e) {
      _recuperarseDeError(errorNombre: e.toString());
    } on FileSystemException catch (e) {
      _recuperarseDeError(errorMedio: 'No se pudo guardar: ${e.message}');
    }
  }

  void _recuperarseDeError({String? errorNombre, String? errorMedio}) {
    if (!mounted) return;
    setState(() {
      _procesando = false;
      _errorNombre = errorNombre;
      _errorMedio = errorMedio;
    });
    if (_medio.esVideo) unawaited(_iniciarVideo());
  }

  // ---------------------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Mientras se mueve el archivo no se permite salir: dejaría la
      // operación a medias.
      canPop: !_procesando,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_medio.esVideo ? 'Confirmar video' : 'Confirmar foto'),
          automaticallyImplyLeading: !_procesando,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.all(8),
                  alignment: Alignment.center,
                  child: _construirVistaPrevia(),
                ),
              ),
              _construirFormulario(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirVistaPrevia() {
    final error = _errorMedio;
    if (error != null) {
      return Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white));
    }

    if (_medio.esVideo) {
      final video = _video;
      if (video == null || !video.value.isInitialized) {
        return const CircularProgressIndicator(color: Colors.white);
      }
      return VisorVideo(controlador: video);
    }

    final imagen = _imagen;
    if (imagen == null) return const SizedBox.shrink();
    return Image(
      image: imagen,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Text(
        'No se pudo cargar la imagen.',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _construirFormulario() {
    final duracion = _medio.duracion;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (duracion != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Duración: ${formatearDuracion(duracion)}'),
              ),
            TextFormField(
              controller: _nombreCtrl,
              enabled: !_procesando,
              maxLength: NombreArchivo.longitudMaxima,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _aceptar(),
              onChanged: (_) {
                if (_errorNombre != null) setState(() => _errorNombre = null);
              },
              decoration: InputDecoration(
                labelText: 'Nombre del archivo',
                border: const OutlineInputBorder(),
                suffixText: _medio.extension,
                errorText: _errorNombre,
                // El mensaje de caracteres no permitidos no cabe en una línea.
                errorMaxLines: 2,
              ),
              validator: NombreArchivo.validar,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _procesando ? null : _cancelar,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _procesando ? null : _aceptar,
                    icon: _procesando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
