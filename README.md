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

Este repositorio contiene el código Dart, el `AndroidManifest.xml` y las pruebas. Las
carpetas de plataforma restantes se generan con el SDK de Flutter.

```bash
# 1. Generar los archivos de Android/iOS que faltan.
#    flutter create no sobrescribe los archivos que ya existen
#    (lib/, test/, pubspec.yaml ni el AndroidManifest.xml de este repo).
flutter create --project-name camara_recursos --org com.anahuac --platforms android,ios .

# 2. Fijar las versiones de las dependencias en pubspec.yaml
flutter pub add camera video_player path_provider path
flutter pub add --dev flutter_lints

# 3. Verificar y ejecutar en un dispositivo físico
flutter analyze
flutter test
flutter run
```

### iOS

Agregar en `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>La app usa la cámara para tomar fotografías y grabar video.</string>
<key>NSMicrophoneUsageDescription</key>
<string>La app usa el micrófono para grabar el audio de los videos.</string>
```

> La cámara no funciona en el emulador de iOS. En el emulador de Android solo hay una
> cámara simulada; para evaluar rendimiento usa un dispositivo físico y
> `flutter run --profile`.

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
