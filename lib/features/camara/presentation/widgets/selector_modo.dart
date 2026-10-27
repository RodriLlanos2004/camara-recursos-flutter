import 'package:flutter/material.dart';

import '../../domain/modo_captura.dart';

/// Alterna entre Foto y Video (RF-01). Se bloquea mientras se graba:
/// cambiar de modo a mitad de una grabación dejaría un archivo huérfano.
class SelectorModo extends StatelessWidget {
  const SelectorModo({
    super.key,
    required this.modo,
    required this.onChanged,
  });

  final ModoCaptura modo;

  /// `null` deshabilita el selector.
  final ValueChanged<ModoCaptura>? onChanged;

  static IconData _icono(ModoCaptura modo) => switch (modo) {
        ModoCaptura.foto => Icons.photo_camera,
        ModoCaptura.video => Icons.videocam,
      };

  @override
  Widget build(BuildContext context) {
    final cambiar = onChanged;
    return SegmentedButton<ModoCaptura>(
      segments: ModoCaptura.values
          .map((m) => ButtonSegment<ModoCaptura>(
                value: m,
                label: Text(m.etiqueta),
                icon: Icon(_icono(m)),
              ))
          .toList(),
      selected: {modo},
      showSelectedIcon: false,
      onSelectionChanged: cambiar == null ? null : (seleccion) => cambiar(seleccion.first),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (estados) => estados.contains(WidgetState.selected) ? Colors.black : Colors.white,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (estados) => estados.contains(WidgetState.selected) ? Colors.white : Colors.transparent,
        ),
      ),
    );
  }
}
