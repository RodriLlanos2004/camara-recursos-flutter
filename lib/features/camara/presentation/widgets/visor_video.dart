import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/formato.dart';

/// Reproductor sin estado propio: el VideoPlayerController lo crea y lo
/// libera la pantalla dueña (ConfirmacionPage). Así solo un lugar decide
/// cuándo se suelta el decodificador de video.
class VisorVideo extends StatelessWidget {
  const VisorVideo({super.key, required this.controlador});

  final VideoPlayerController controlador;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controlador,
      builder: (context, valor, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: GestureDetector(
                onTap: () => valor.isPlaying ? controlador.pause() : controlador.play(),
                child: AspectRatio(
                  aspectRatio: valor.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // VideoPlayer también se dibuja con un widget Texture:
                      // los fotogramas decodificados quedan en la GPU.
                      VideoPlayer(controlador),
                      if (!valor.isPlaying)
                        const CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(controlador, allowScrubbing: true),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${formatearDuracion(valor.position)} / ${formatearDuracion(valor.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}
