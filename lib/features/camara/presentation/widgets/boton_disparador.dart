import 'package:flutter/material.dart';

import '../../../../core/theme/app_tema.dart';
import '../../domain/modo_captura.dart';

/// Botón circular de captura. Su forma comunica el estado:
/// - Foto: círculo blanco.
/// - Video detenido: círculo rojo.
/// - Video grabando: cuadrado rojo (detener).
class BotonDisparador extends StatelessWidget {
  const BotonDisparador({
    super.key,
    required this.modo,
    required this.grabando,
    required this.onPressed,
  });

  final ModoCaptura modo;
  final bool grabando;

  /// `null` deshabilita el botón (cámara no lista u operación en curso).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final habilitado = onPressed != null;
    final colorInterior = modo == ModoCaptura.foto ? Colors.white : AppTema.colorGrabacion;
    final etiqueta = switch (modo) {
      ModoCaptura.foto => 'Tomar fotografía',
      ModoCaptura.video => grabando ? 'Detener grabación' : 'Iniciar grabación',
    };

    return Semantics(
      button: true,
      label: etiqueta,
      child: GestureDetector(
        onTap: onPressed,
        child: Opacity(
          opacity: habilitado ? 1 : 0.4,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: grabando ? 30 : 58,
              height: grabando ? 30 : 58,
              decoration: BoxDecoration(
                color: colorInterior,
                borderRadius: BorderRadius.circular(grabando ? 6 : 29),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
