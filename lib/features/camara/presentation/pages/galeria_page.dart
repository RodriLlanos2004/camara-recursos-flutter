import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/formato.dart';
import '../../data/almacenamiento_repository.dart';
import '../../domain/elemento_galeria.dart';
import '../../domain/medio_capturado.dart';

/// RF-04: archivos confirmados en el directorio persistente, más un panel
/// que muestra el uso de la zona temporal para demostrar la limpieza (RF-03).
class GaleriaPage extends StatefulWidget {
  const GaleriaPage({super.key, required this.repositorio});

  final AlmacenamientoRepository repositorio;

  @override
  State<GaleriaPage> createState() => _GaleriaPageState();
}

class _DatosGaleria {
  const _DatosGaleria(this.elementos, this.resumen);

  final List<ElementoGaleria> elementos;
  final ResumenAlmacenamiento resumen;
}

class _GaleriaPageState extends State<GaleriaPage> {
  late Future<_DatosGaleria> _futuro;

  AlmacenamientoRepository get _repo => widget.repositorio;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<_DatosGaleria> _cargar() async =>
      _DatosGaleria(await _repo.listarGaleria(), await _repo.resumen());

  void _recargar() => setState(() => _futuro = _cargar());

  Future<void> _limpiarTemporales() async {
    final borrados = await _repo.limpiarTemporales();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$borrados archivo(s) temporal(es) eliminado(s).')),
    );
    _recargar();
  }

  Future<void> _eliminar(ElementoGaleria elemento) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('¿Eliminar "${elemento.nombre}" de forma permanente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true) return;

    await _repo.eliminarDeGaleria(elemento);
    // La miniatura decodificada también se saca de la caché de imágenes.
    unawaited(_miniatura(elemento).evict());
    _recargar();
  }

  /// Miniatura decodificada a 160 px de ancho: una foto completa ocuparía
  /// decenas de MB por cada elemento de la lista.
  ImageProvider _miniatura(ElementoGaleria elemento) =>
      ResizeImage(FileImage(File(elemento.ruta)), width: 160);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galería'),
        actions: [
          IconButton(
            tooltip: 'Limpiar temporales ahora',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _limpiarTemporales,
          ),
        ],
      ),
      body: FutureBuilder<_DatosGaleria>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'No se pudo leer el almacenamiento: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final datos = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PanelAlmacenamiento(resumen: datos.resumen),
              const SizedBox(height: 16),
              if (datos.elementos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Aún no hay capturas guardadas.\nToma una foto o graba un video y pulsa "Aceptar".',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...datos.elementos.map((e) => _FilaElemento(
                      elemento: e,
                      miniatura: e.tipo == TipoMedio.foto ? _miniatura(e) : null,
                      onEliminar: () => _eliminar(e),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _PanelAlmacenamiento extends StatelessWidget {
  const _PanelAlmacenamiento({required this.resumen});

  final ResumenAlmacenamiento resumen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Almacenamiento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _FilaDato(
              icono: Icons.folder_special_outlined,
              etiqueta: 'Documentos (persistente)',
              valor: '${resumen.archivosGaleria} · ${formatearBytes(resumen.bytesGaleria)}',
            ),
            _FilaDato(
              icono: Icons.auto_delete_outlined,
              etiqueta: 'Temporal (caché)',
              valor: '${resumen.archivosTemporales} · ${formatearBytes(resumen.bytesTemporales)}',
            ),
            if (resumen.archivosTemporales > 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Hay capturas sin confirmar en la zona temporal. Se borran al '
                  'cerrar la app o con el botón de limpieza.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.icono, required this.etiqueta, required this.valor});

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, size: 20, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(child: Text(etiqueta)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FilaElemento extends StatelessWidget {
  const _FilaElemento({
    required this.elemento,
    required this.miniatura,
    required this.onEliminar,
  });

  final ElementoGaleria elemento;
  final ImageProvider? miniatura;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final imagen = miniatura;
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 56,
            height: 56,
            child: imagen == null
                ? const ColoredBox(
                    color: Colors.black12,
                    child: Icon(Icons.videocam_outlined),
                  )
                : Image(
                    image: imagen,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                  ),
          ),
        ),
        title: Text(elemento.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${formatearBytes(elemento.tamanoBytes)} · ${formatearFecha(elemento.modificado)}',
        ),
        trailing: IconButton(
          tooltip: 'Eliminar',
          icon: const Icon(Icons.delete_outline),
          onPressed: onEliminar,
        ),
      ),
    );
  }
}
