import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../data/almacenamiento_repository.dart';
import '../../domain/medio_capturado.dart';
import '../../domain/modo_captura.dart';
import '../widgets/boton_disparador.dart';
import '../widgets/indicador_grabacion.dart';
import '../widgets/selector_modo.dart';
import 'confirmacion_page.dart';
import 'galeria_page.dart';

/// Pantalla principal: vista previa, captura de foto y grabación de video.
///
/// Es la dueña del hardware. Implementa WidgetsBindingObserver (RT-02) para
/// enterarse de cuándo la app pasa a segundo plano y soltar la cámara.
class CamaraPage extends StatefulWidget {
  const CamaraPage({super.key, required this.repositorio});

  final AlmacenamientoRepository repositorio;

  @override
  State<CamaraPage> createState() => _CamaraPageState();
}

class _CamaraPageState extends State<CamaraPage> with WidgetsBindingObserver {
  // --- Hardware --------------------------------------------------------------
  List<CameraDescription> _camaras = const [];
  CameraDescription? _camaraActual;

  /// Regla de la pantalla: como máximo UN controlador vivo a la vez.
  /// `null` significa que el hardware está liberado.
  CameraController? _controlador;

  // --- Estado de la pantalla -------------------------------------------------
  ModoCaptura _modo = ModoCaptura.foto;
  bool _ocupado = false; // captura o cambio de modo en curso
  bool _inicializando = false;
  bool _enPrimerPlano = true;
  bool _pantallaEncima = false; // confirmación o galería tapan esta pantalla
  bool _grabacionInterrumpida = false;
  String? _errorFatal;

  // --- Temporizador de grabación (RF-01) ------------------------------------
  final Stopwatch _cronometro = Stopwatch();
  Timer? _temporizador;
  final ValueNotifier<Duration> _tiempoGrabacion = ValueNotifier(Duration.zero);

  AlmacenamientoRepository get _repo => widget.repositorio;

  bool get _grabando => _controlador?.value.isRecordingVideo ?? false;

  bool get _camaraLista {
    final c = _controlador;
    return c != null && c.value.isInitialized;
  }

  // ===========================================================================
  // Ciclo de vida del widget
  // ===========================================================================
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_cargarCamaras());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detenerTemporizador();
    _tiempoGrabacion.dispose();

    // RT-02: el controlador se libera de inmediato. dispose() de un widget
    // es síncrono, así que la liberación (asíncrona) se lanza sin esperarla.
    final controlador = _controlador;
    _controlador = null;
    if (controlador != null) unawaited(controlador.dispose());

    // RF-03: al destruir la pantalla se escanea y limpia el directorio temporal.
    unawaited(_repo.limpiarTemporales());
    super.dispose();
  }

  // ===========================================================================
  // Ciclo de vida de la aplicación (RT-02)
  // ===========================================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    debugPrint('[Ciclo de vida] $estado');
    switch (estado) {
      case AppLifecycleState.resumed:
        _enPrimerPlano = true;
        // Si hay otra pantalla encima, la cámara se reabre al volver a ella.
        if (!_pantallaEncima && _controlador == null) {
          unawaited(_iniciarCamaraActual());
        }
        if (_grabacionInterrumpida) {
          _grabacionInterrumpida = false;
          _mostrarMensaje(
            'La grabación se detuvo al salir de la app y el video incompleto se eliminó.',
          );
        }

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Estados transitorios: panel de notificaciones, llamada entrante o
        // el propio diálogo de permisos de la cámara. Liberar aquí cortaría
        // la solicitud de permiso, así que se espera a `paused`.
        break;

      case AppLifecycleState.paused:
        // La app ya no es visible: se suelta el sensor, la memoria de los
        // búferes y la textura en la GPU.
        _enPrimerPlano = false;
        unawaited(_liberarCamara());

      case AppLifecycleState.detached:
        // La app se está cerrando: hardware fuera y limpieza de temporales.
        // El SO no garantiza entregar este estado (puede matar el proceso sin
        // avisar); por eso main.dart también limpia al arrancar.
        _enPrimerPlano = false;
        unawaited(_liberarCamara());
        unawaited(_repo.limpiarTemporales());
    }
  }

  // ===========================================================================
  // Gestión del controlador
  // ===========================================================================
  Future<void> _cargarCamaras() async {
    try {
      final camaras = await availableCameras();
      if (!mounted) return;
      if (camaras.isEmpty) {
        setState(() => _errorFatal = 'Este dispositivo no tiene cámaras disponibles.');
        return;
      }
      _camaras = camaras;
      _camaraActual = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camaras.first,
      );
      await _iniciarCamaraActual();
    } on CameraException catch (e) {
      _mostrarErrorCamara(e, fatal: true);
    }
  }

  Future<void> _iniciarCamaraActual() async {
    final descripcion = _camaraActual;
    if (descripcion == null || _inicializando) return;
    _inicializando = true;

    // Nunca dos controladores vivos: primero se libera el anterior.
    await _liberarCamara();

    final controlador = CameraController(
      descripcion,
      ResolutionPreset.high,
      enableAudio: true, // el mismo controlador sirve para foto y video
    );

    try {
      await controlador.initialize();

      // La inicialización tarda: si mientras tanto la app se fue a segundo
      // plano o se abrió otra pantalla, se libera en lugar de quedar viva.
      if (!mounted || !_enPrimerPlano || _pantallaEncima) {
        await controlador.dispose();
        return;
      }
      setState(() {
        _controlador = controlador;
        _errorFatal = null;
      });
      debugPrint('[Cámara] Inicializada: ${descripcion.name} (textura en GPU)');
    } on CameraException catch (e) {
      await controlador.dispose();
      _mostrarErrorCamara(e, fatal: true);
    } finally {
      _inicializando = false;
    }
  }

  /// Libera el hardware. Si se estaba grabando, el video incompleto se
  /// detiene y se borra: es basura temporal (RF-03).
  Future<void> _liberarCamara() async {
    final controlador = _controlador;
    if (controlador == null) return;

    // Primero se quita de la interfaz para que CameraPreview no se construya
    // con un controlador en proceso de liberación.
    _controlador = null;
    _detenerTemporizador();
    if (mounted) setState(() {});

    if (controlador.value.isRecordingVideo) {
      try {
        final incompleto = await controlador.stopVideoRecording();
        await _repo.descartarTemporal(incompleto.path);
        _grabacionInterrumpida = true;
      } on CameraException catch (e) {
        debugPrint('[Cámara] No se pudo detener la grabación: ${e.code}');
      }
    }

    await controlador.dispose();
    debugPrint('[Cámara] Controlador liberado (CameraController.dispose)');
  }

  Future<void> _cambiarCamara() async {
    final actual = _camaraActual;
    if (actual == null || _camaras.length < 2 || _ocupado || _inicializando) return;
    final indice = _camaras.indexOf(actual);
    _camaraActual = _camaras[(indice + 1) % _camaras.length];
    await _iniciarCamaraActual();
  }

  // ===========================================================================
  // Captura (RF-01)
  // ===========================================================================
  Future<void> _tomarFoto() async {
    final controlador = _controlador;
    if (controlador == null || !controlador.value.isInitialized ||
        controlador.value.isTakingPicture || _ocupado) {
      return;
    }

    setState(() => _ocupado = true);
    try {
      final foto = await controlador.takePicture();
      await _abrirConfirmacion(
        MedioCapturado(rutaTemporal: foto.path, tipo: TipoMedio.foto),
      );
    } on CameraException catch (e) {
      _mostrarErrorCamara(e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _alternarGrabacion() async {
    final controlador = _controlador;
    if (controlador == null || !controlador.value.isInitialized || _ocupado) return;

    if (controlador.value.isRecordingVideo) {
      await _detenerGrabacion(controlador);
    } else {
      await _iniciarGrabacion(controlador);
    }
  }

  Future<void> _iniciarGrabacion(CameraController controlador) async {
    setState(() => _ocupado = true);
    try {
      await controlador.prepareForVideoRecording();
      await controlador.startVideoRecording();
      _iniciarTemporizador();
    } on CameraException catch (e) {
      _mostrarErrorCamara(e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _detenerGrabacion(CameraController controlador) async {
    setState(() => _ocupado = true);
    try {
      final video = await controlador.stopVideoRecording();
      final duracion = _cronometro.elapsed;
      _detenerTemporizador();
      await _abrirConfirmacion(
        MedioCapturado(rutaTemporal: video.path, tipo: TipoMedio.video, duracion: duracion),
      );
    } on CameraException catch (e) {
      _detenerTemporizador();
      _mostrarErrorCamara(e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _iniciarTemporizador() {
    _tiempoGrabacion.value = Duration.zero;
    _cronometro
      ..reset()
      ..start();
    // Se consulta 4 veces por segundo, pero el valor se redondea al segundo:
    // ValueNotifier solo avisa cuando el valor cambia, así que la etiqueta
    // se redibuja una vez por segundo y nunca va retrasada.
    _temporizador = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _tiempoGrabacion.value = Duration(seconds: _cronometro.elapsed.inSeconds);
    });
  }

  void _detenerTemporizador() {
    _temporizador?.cancel();
    _temporizador = null;
    _cronometro.stop();
  }

  // ===========================================================================
  // Navegación (RF-02)
  // ===========================================================================

  /// Abre otra pantalla encima de la cámara con el flujo de vídeo en pausa:
  /// mientras no se ve, no se procesan fotogramas.
  Future<T?> _navegarSobreCamara<T>(Route<T> ruta) async {
    _pantallaEncima = true;
    final controlador = _controlador;
    if (controlador != null &&
        controlador.value.isInitialized &&
        !controlador.value.isPreviewPaused) {
      try {
        await controlador.pausePreview();
        debugPrint('[Cámara] Vista previa en pausa');
      } on CameraException catch (e) {
        debugPrint('[Cámara] No se pudo pausar: ${e.code}');
      }
    }

    if (!mounted) return null;
    final resultado = await Navigator.of(context).push<T>(ruta);
    _pantallaEncima = false;

    if (mounted && _enPrimerPlano) await _reanudarVistaPrevia();
    return resultado;
  }

  Future<void> _reanudarVistaPrevia() async {
    final controlador = _controlador;
    // Si la app pasó a segundo plano mientras había otra pantalla encima,
    // el controlador se liberó: se crea de nuevo.
    if (controlador == null || !controlador.value.isInitialized) {
      await _iniciarCamaraActual();
      return;
    }
    if (controlador.value.isPreviewPaused) {
      try {
        await controlador.resumePreview();
        debugPrint('[Cámara] Vista previa reanudada');
      } on CameraException catch (e) {
        _mostrarErrorCamara(e);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _abrirConfirmacion(MedioCapturado medio) async {
    final guardado = await _navegarSobreCamara<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ConfirmacionPage(medio: medio, repositorio: _repo),
      ),
    );

    // RF-03: cualquier salida que no sea "Aceptar" (Cancelar, botón atrás,
    // gesto de regreso) deja el archivo como basura y se borra de inmediato.
    if (guardado == true) {
      _mostrarMensaje('Guardado en la galería.');
    } else {
      await _repo.descartarTemporal(medio.rutaTemporal);
    }
  }

  Future<void> _abrirGaleria() async {
    if (_grabando || _ocupado) return;
    await _navegarSobreCamara<void>(
      MaterialPageRoute<void>(builder: (_) => GaleriaPage(repositorio: _repo)),
    );
  }

  // ===========================================================================
  // Mensajes
  // ===========================================================================
  String _describirError(CameraException e) => switch (e.code) {
        'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
          'Permiso de cámara denegado. Actívalo en los ajustes de la aplicación.',
        'CameraAccessRestricted' => 'El acceso a la cámara está restringido en este dispositivo.',
        'AudioAccessDenied' || 'AudioAccessDeniedWithoutPrompt' =>
          'Permiso de micrófono denegado: se necesita para grabar video con sonido.',
        'AudioAccessRestricted' => 'El acceso al micrófono está restringido en este dispositivo.',
        _ => 'Error de cámara (${e.code}): ${e.description ?? 'sin detalle'}',
      };

  void _mostrarErrorCamara(CameraException e, {bool fatal = false}) {
    debugPrint('[Cámara] ${e.code}: ${e.description}');
    if (!mounted) return;
    if (fatal) {
      setState(() => _errorFatal = _describirError(e));
    } else {
      _mostrarMensaje(_describirError(e));
    }
  }

  void _mostrarMensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  // ===========================================================================
  // Interfaz
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _construirBarraSuperior(),
            Expanded(child: Center(child: _construirVistaPrevia())),
            _construirControles(),
          ],
        ),
      ),
    );
  }

  Widget _construirBarraSuperior() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Galería',
            color: Colors.white,
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _grabando || _ocupado ? null : _abrirGaleria,
          ),
          const Expanded(
            child: Text(
              'Cámara',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Cambiar cámara',
            color: Colors.white,
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: _camaras.length < 2 || _grabando || _ocupado || _inicializando
                ? null
                : _cambiarCamara,
          ),
        ],
      ),
    );
  }

  Widget _construirVistaPrevia() {
    final error = _errorFatal;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 64),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _camaras.isEmpty ? _cargarCamaras : _iniciarCamaraActual,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final controlador = _controlador;
    if (controlador == null || !controlador.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    // RT-01: CameraPreview construye internamente un widget Texture con el
    // textureId del controlador. Los fotogramas van del sensor a una textura
    // de la GPU y el compositor de Flutter la dibuja directamente: ningún
    // fotograma pasa por Dart como Uint8List.
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        CameraPreview(controlador),
        if (_grabando)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: IndicadorGrabacion(tiempo: _tiempoGrabacion),
          ),
      ],
    );
  }

  Widget _construirControles() {
    final puedeCapturar = _camaraLista && !_ocupado;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectorModo(
            modo: _modo,
            onChanged: _grabando || _ocupado ? null : (modo) => setState(() => _modo = modo),
          ),
          const SizedBox(height: 20),
          BotonDisparador(
            modo: _modo,
            grabando: _grabando,
            onPressed: !puedeCapturar
                ? null
                : _modo == ModoCaptura.foto
                    ? _tomarFoto
                    : _alternarGrabacion,
          ),
        ],
      ),
    );
  }
}
