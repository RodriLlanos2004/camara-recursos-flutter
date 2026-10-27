import 'package:flutter/material.dart';

import '../../../../core/theme/app_tema.dart';
import '../../../../core/utils/formato.dart';

/// Temporizador visible durante la grabación (RF-01).
///
/// Escucha un ValueNotifier en lugar de depender de setState: cuando cambia
/// el segundo, solo se reconstruye esta etiqueta y no la pantalla completa
/// (que incluye la vista previa de la cámara).
class IndicadorGrabacion extends StatelessWidget {
  const IndicadorGrabacion({super.key, required this.tiempo});

  final ValueNotifier<Duration> tiempo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, color: AppTema.colorGrabacion, size: 14),
          const SizedBox(width: 6),
          ValueListenableBuilder<Duration>(
            valueListenable: tiempo,
            builder: (context, duracion, _) => Text(
              formatearDuracion(duracion),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()], // dígitos de ancho fijo
              ),
            ),
          ),
        ],
      ),
    );
  }
}
