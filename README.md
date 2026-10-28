# Cámara y Recursos — Control de hardware y gestión de memoria en Flutter

Práctica de **Programación de Dispositivos Móviles**: captura de fotografía y video con
la cámara del dispositivo, renderizado acelerado por GPU, liberación estricta de
recursos y gestión del almacenamiento temporal y persistente.

El reporte técnico está en [`docs/reporte_tecnico.md`](docs/reporte_tecnico.md).

## Funcionalidades

- Alternar entre modo **Foto** y modo **Video**, con temporizador visible durante la grabación.
- Pantalla de **confirmación** después de cada captura: vista previa (imagen o reproductor de video) y nombre personalizado para el archivo.
- **Aceptar** mueve el archivo a la galería persistente con el nombre elegido; **Cancelar** lo borra al instante.
- **Galería** con las capturas guardadas y un panel que muestra cuánto ocupa la zona temporal.
- Cambio entre cámara trasera y frontal.

## Puesta en marcha

El repositorio ya incluye los proyectos nativos de Android e iOS, las versiones fijadas
de las dependencias (`pubspec.lock`) y los permisos de cámara y micrófono de ambas
plataformas. Compilado y probado con Flutter 3.44 (canal estable).

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # dispositivo o emulador Android conectado
```

> En el emulador de Android la cámara puede ser una escena virtual o la webcam del PC
> (`hw.camera.back=webcam0` en el `config.ini` del AVD). La cámara no funciona en el
> simulador de iOS. Para medir rendimiento usa `flutter run --profile`.

Resultados de las pruebas manuales y evidencias: sección 7 de
[`docs/reporte_tecnico.md`](docs/reporte_tecnico.md) y carpeta [`docs/evidencias/`](docs/evidencias/).

## Estructura (arquitectura por capas, Feature-First)

```text
lib/
├── main.dart                      Arranque: orientación, limpieza inicial de temporales
├── app.dart                       MaterialApp
├── core/
│   ├── theme/app_tema.dart
│   └── utils/formato.dart         Duraciones, tamaños y fechas
└── features/camara/
    ├── domain/                    Modelos y reglas puras (sin Flutter)
    │   ├── modo_captura.dart
    │   ├── medio_capturado.dart   Captura que vive en la zona temporal
    │   ├── elemento_galeria.dart  Archivo confirmado + resumen de almacenamiento
    │   └── nombre_archivo.dart    Validación y normalización del nombre
    ├── data/
    │   └── almacenamiento_repository.dart   Única puerta al sistema de archivos
    └── presentation/
        ├── pages/
        │   ├── camara_page.dart        Dueña del CameraController + WidgetsBindingObserver
        │   ├── confirmacion_page.dart  Vista previa, nombre, Aceptar/Cancelar
        │   └── galeria_page.dart       Archivos persistentes y panel de almacenamiento
        └── widgets/
            ├── boton_disparador.dart
            ├── indicador_grabacion.dart
            ├── selector_modo.dart
            └── visor_video.dart
```

## Pruebas

```bash
flutter test
```

Cubren la lógica pura: validación y normalización de nombres, extensión de las
capturas y funciones de formato. El flujo de cámara se verifica manualmente con la
lista de casos del reporte técnico.
