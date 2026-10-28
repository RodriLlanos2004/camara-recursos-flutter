# Reporte técnico — Control de hardware, procesamiento multimedia y gestión de recursos

**Asignatura:** Programación de Dispositivos Móviles
**Profesor:** Fernando Martínez Chacón
**Alumno:** Rodrigo Sebastián Llanos Yáñez

---

## 1. Resumen

La aplicación captura fotografías y videos con la cámara del dispositivo, muestra cada
captura en una pantalla de confirmación donde el usuario le asigna un nombre y solo
conserva los archivos aceptados. El diseño persigue tres objetivos técnicos:

1. Que la vista previa de la cámara se componga en la **GPU**, sin que los fotogramas
   pasen por el hilo de Dart.
2. Que el hardware y los búferes se **liberen** en cuanto la app deja de usarlos.
3. Que el almacenamiento **no acumule basura**: lo temporal se borra, lo persistente
   solo contiene lo que el usuario confirmó.

## 2. Arquitectura

Organización **Feature-First** con tres capas dentro de `features/camara/`:

| Capa | Responsabilidad | No contiene |
|---|---|---|
| `domain/` | Modelos (`MedioCapturado`, `ElementoGaleria`) y reglas puras (`NombreArchivo`) | Flutter, plugins ni E/S |
| `data/` | `AlmacenamientoRepository`: zonas temporal y persistente, mover, borrar, escanear | Widgets |
| `presentation/` | Pantallas, widgets y ciclo de vida del hardware | Acceso directo a archivos |

Dependencias: `presentation → data → domain`. El repositorio se crea una sola vez en
`main.dart` y se inyecta por constructor a las pantallas.

```text
CamaraPage ──takePicture / stopVideoRecording──▶ archivo en zona TEMPORAL
    │
    └─push──▶ ConfirmacionPage
                 ├─ Aceptar ──▶ repositorio.guardarEnGaleria ──▶ zona PERSISTENTE
                 └─ Cancelar ─▶ repositorio.descartarTemporal ──▶ archivo borrado
```

## 3. Renderizado acelerado por GPU (RT-01)

### 3.1 Cómo llega un fotograma a la pantalla

```text
Sensor ─▶ Camera HAL / CameraX (Android) · AVFoundation (iOS)
       ─▶ SurfaceTexture / CVPixelBuffer  (memoria de la GPU)
       ─▶ registrado en el motor de Flutter con un textureId
       ─▶ widget Texture(textureId) dentro de CameraPreview
       ─▶ el compositor del motor dibuja la textura como una capa más
```

`CameraPreview(controlador)` construye internamente un widget `Texture` con el
`textureId` que el plugin obtiene al inicializar el `CameraController`. El motor de
Flutter compone esa textura directamente en la GPU, igual que cualquier otra capa
de la escena.

### 3.2 Lo que **no** ocurre

- **Ningún fotograma viaja a Dart.** La app nunca llama a `startImageStream()`, que es
  la única API del plugin que entrega fotogramas como `CameraImage` con planos
  `Uint8List`. Usarla obligaría a copiar ~3 MB por fotograma a 30 fps al heap de Dart
  y a procesarlos en el hilo principal: alrededor de 90 MB/s de tráfico por la CPU.
- **No hay conversión de formato en la CPU.** La conversión YUV → RGB y el escalado
  los hace la GPU al muestrear la textura.
- Lo mismo aplica al reproductor: `VideoPlayer(controlador)` también es un `Texture`;
  el decodificador de hardware escribe los fotogramas en la textura.

En consecuencia, el hilo de Dart solo reconstruye widgets cuando cambia el estado de la
interfaz (cambio de modo, segundo del temporizador), no 30 veces por segundo.

### 3.3 Configuración en Android

`android/app/src/main/AndroidManifest.xml` declara explícitamente:

```xml
<application ... android:hardwareAccelerated="true">
```

Es el valor por defecto desde Android 4.0 (API 14); se deja escrito porque lo exige la
práctica y documenta la intención. Con él, la ventana de la actividad se compone en la
GPU y las `SurfaceTexture` de la cámara se pueden muestrear sin copiarlas a memoria
del sistema.

## 4. Gestión del ciclo de vida (RT-02)

### 4.1 Ciclo de vida de la aplicación

`_CamaraPageState` usa el mixin `WidgetsBindingObserver` y se registra en `initState`
(`addObserver`) y se da de baja en `dispose` (`removeObserver`).

| Estado | Acción | Motivo |
|---|---|---|
| `inactive`, `hidden` | Ninguna | Transitorios: panel de notificaciones, llamada, o el diálogo de permisos de la propia cámara. Liberar aquí cortaría la solicitud de permiso. |
| `paused` | `CameraController.dispose()`; si había grabación, se detiene y el video incompleto se borra | La app ya no se ve: se libera el sensor, los búferes en RAM y la textura en VRAM, y otra app puede usar la cámara |
| `detached` | `dispose()` + limpieza de temporales | La app se cierra |
| `resumed` | Se crea un controlador nuevo | Solo si no hay otra pantalla encima |

Protecciones adicionales:

- **Un solo controlador vivo.** `_iniciarCamaraActual()` libera el anterior antes de
  crear el nuevo (también al cambiar entre cámara trasera y frontal).
- **Inicialización interrumpida.** Si la app pasa a segundo plano mientras
  `initialize()` está en curso, al terminar se detecta y el controlador se libera en
  lugar de quedar vivo.
- **El controlador se retira de la interfaz antes de liberarlo**, para que
  `CameraPreview` nunca se construya con un controlador en proceso de destrucción.

### 4.2 Navegación a la confirmación

Al capturar, la cámara llama a `pausePreview()` antes de abrir `ConfirmacionPage`
(RF-02): mientras el usuario revisa la captura no se procesan fotogramas. Al volver se
llama a `resumePreview()`; si en el intervalo la app pasó a segundo plano y el
controlador se liberó, se crea uno nuevo.

### 4.3 Reproductor de video

`ConfirmacionPage` es la única dueña del `VideoPlayerController`:

- se pausa cuando la app deja de estar en `resumed`;
- se destruye con `dispose()` al salir de la pantalla;
- se destruye **antes** de mover o borrar el archivo, porque el decodificador lo
  mantiene abierto.

### 4.4 Memoria de imágenes

Una fotografía de 12 MP decodificada ocupa unos 48 MB (4 bytes por píxel). Por eso:

- La confirmación decodifica la foto con `ResizeImage` al ancho físico de la pantalla.
- La galería decodifica miniaturas de 160 px.
- Al cerrar la confirmación o borrar un archivo se llama a `evict()` para sacar el
  bitmap de la caché global de imágenes.

### 4.5 Temporizador de grabación

`Timer.periodic` + `Stopwatch`, cancelados en `dispose` y al liberar la cámara. El
valor se publica en un `ValueNotifier<Duration>` redondeado al segundo: solo se
reconstruye la etiqueta del temporizador, una vez por segundo, y no la pantalla que
contiene la vista previa.

## 5. Almacenamiento (RF-03, RF-04)

| Zona | API | Contenido | Ciclo de vida |
|---|---|---|---|
| Temporal | `getTemporaryDirectory()` | Capturas sin confirmar | El SO puede vaciarla si falta espacio; la app la limpia activamente |
| Persistente | `getApplicationDocumentsDirectory()/capturas` | Capturas aceptadas | Sobrevive a reinicios; se borra al desinstalar |

### 5.1 Cuándo se borra lo temporal

| Momento | Dónde |
|---|---|
| Botón **Cancelar**, botón atrás o gesto de regreso | `ConfirmacionPage._cancelar` y, como respaldo, `CamaraPage._abrirConfirmacion` (idempotente) |
| Grabación interrumpida al pasar a segundo plano | `CamaraPage._liberarCamara` |
| Destrucción de la pantalla | `CamaraPage.dispose` |
| Cierre de la app (`detached`) | `CamaraPage.didChangeAppLifecycleState` |
| **Arranque de la app** | `main.dart` |

La limpieza en el arranque es una red de seguridad: Android puede terminar el proceso
sin entregar `detached` (por ejemplo, al deslizar la app fuera de recientes), así que
la limpieza de cierre no está garantizada.

**Alcance del escaneo.** `limpiarTemporales()` recorre el directorio temporal de forma
recursiva y borra solo archivos multimedia (`.jpg`, `.jpeg`, `.png`, `.heic`, `.mp4`,
`.mov`, `.3gp`, `.temp`). No se vacía el directorio completo porque también lo usan el
motor de Flutter y otros plugins.

### 5.2 Paso a la zona persistente

`guardarEnGaleria()`:

1. Comprueba que el temporal existe y que no hay otro archivo con el mismo nombre.
2. Usa `File.rename`: en el mismo sistema de archivos solo cambia la entrada del
   directorio, sin copiar bytes.
3. Si el SO no lo permite, copia y borra el original. Nunca quedan dos copias.

El nombre se valida (letras, acentos, números, espacio, guion y guion bajo; máximo 60
caracteres), se normaliza (espacios → `_`) y conserva la extensión original. Se
excluyen `/`, `\` y `.` para impedir rutas como `../` o cambiar la extensión.

## 6. Trazabilidad de requerimientos

| Requerimiento | Implementación |
|---|---|
| RF-01 Captura dual | `SelectorModo`, `BotonDisparador`, `IndicadorGrabacion`, `CamaraPage._tomarFoto` / `_alternarGrabacion` |
| RF-02 Vista previa y renombrado | `CamaraPage._navegarSobreCamara` (`pausePreview`), `ConfirmacionPage` |
| RF-03 Limpieza de temporales | `AlmacenamientoRepository.descartarTemporal` / `limpiarTemporales`; ver §5.1 |
| RF-04 Galería persistente | `AlmacenamientoRepository.guardarEnGaleria`, `GaleriaPage` |
| RT-01 GPU | `CameraPreview` (Texture), `android:hardwareAccelerated="true"`, sin `startImageStream` |
| RT-02 Liberación de recursos | `WidgetsBindingObserver`, `CameraController.dispose`, `VideoPlayerController.dispose` |

## 7. Pruebas

### 7.1 Automatizadas

`flutter test` ejecuta las pruebas de la lógica pura (`test/widget_test.dart`).

### 7.2 Manuales

**Entorno de ejecución.** Emulador de Android Studio `Medium_Phone_API_37.0`
(Android 17, x86_64, aceleración por hardware WHPX), APK compilado en modo *release*
con Flutter 3.44. Cámara del emulador: escena emulada. Las acciones se ejecutaron con
`adb shell input` y la consola se leyó con `adb logcat -s flutter:I`. El registro
completo está en [`evidencias/logcat_flutter.txt`](evidencias/logcat_flutter.txt).

El registro confirma además que el motor usa **Impeller** sobre OpenGL ES
(`Using the Impeller rendering backend (OpenGLES)`), es decir, la composición de la
interfaz y de la textura de la cámara se hace en la GPU.

| # | Caso | Resultado obtenido | Evidencia |
|---|---|---|---|
| 1 | Tomar foto → **Cancelar** | ✅ Consola: `Descartado: CAP…jpg`. Galería: *Temporal 0 · 0 B* | `04_galeria_tras_cancelar.png` |
| 2 | Tomar foto → nombre `Practica_camara` → **Aceptar** | ✅ `Guardado en documentos: …/capturas/Practica_camara.jpg`; aparece en la galería y la zona temporal sigue en 0 (se movió, no se copió) | `01_confirmacion_foto.png`, `08_galeria_foto_guardada.png` |
| 3 | Aceptar con un nombre ya existente | ✅ Mensaje *"Ya existe un archivo con ese nombre en la galería."*; no se sobrescribe | `05_nombre_duplicado.png` |
| 4 | Nombre `mi.foto/1` | ✅ El validador lo rechaza. Se corrigió un detalle visual: el mensaje se cortaba en una línea (`errorMaxLines: 2`) | `06_nombre_invalido.png` |
| 5 | Grabar 10 s → **Aceptar** | ✅ Temporizador visible (00:06 en la captura), selector de modo y galería bloqueados durante la grabación; el video de 00:10 se reproduce en la confirmación y se guarda como `Video_prueba.mp4` | `09_grabando_temporizador.png`, `10_confirmacion_video.png` |
| 6 | Grabar y pulsar **Inicio** | ✅ Consola: `inactive → hidden → paused`, `Descartado: REC…mp4`, `Controlador liberado`. Al volver aparece el aviso de grabación interrumpida | `11_…`, `13_regreso_aviso.png` |
| 7 | Indicador de cámara del sistema | ✅ El punto verde de privacidad de Android está encendido durante la grabación y desaparece en la pantalla de Inicio: el sistema confirma que la app soltó la cámara | `11_grabando_antes_de_inicio.png`, `12_inicio_sin_indicador.png` |
| 8 | Volver a la app | ✅ `resumed` → `Inicializada: 1 (textura en GPU)`; la vista previa regresa | `13_regreso_aviso.png` |
| 9 | Botón **atrás** del sistema en la confirmación | ✅ Mismo efecto que Cancelar: `Descartado: CAP…jpg` | `07_galeria_tras_atras.png` |
| 10 | Foto sin confirmar → cierre forzado (`am force-stop`, que no entrega `detached`) → reabrir | ✅ El nuevo arranque registra `Limpieza completa: 1 archivo(s) eliminado(s)`; la galería muestra *Temporal 0* | `14_galeria_tras_reinicio.png` |

**Comprobaciones adicionales observadas en la consola:**

- **Un solo controlador vivo.** Al cambiar de cámara, `Controlador liberado` aparece
  antes de `Inicializada` (19:33:10.552 → 19:33:10.636).
- **Pausa de la vista previa (RF-02).** Cada apertura de la confirmación o de la galería
  registra `Vista previa en pausa`, y cada regreso `Vista previa reanudada`.
- **Permisos.** El primer `inactive` corresponde al diálogo de permisos de Android; como
  la cámara solo se libera en `paused`, la solicitud no se interrumpió y la cámara se
  inicializó en cuanto se concedió (`resumed` → `Inicializada`).

**Pendiente.** La medición de memoria con Flutter DevTools (repetir capturas canceladas
y comprobar que la memoria vuelve a su nivel base) requiere ejecutar la app en modo
*profile* conectada a DevTools; no forma parte de estas pruebas.

## 8. Limitaciones conocidas

- El estado `detached` no está garantizado por el SO; se compensa con la limpieza al
  arrancar.
- La orientación está fija en vertical para no reconstruir la textura en cada giro.
- `enableAudio: true` hace que el permiso de micrófono se solicite al abrir la cámara,
  aunque el usuario solo tome fotos, porque el mismo controlador sirve para ambos modos.

## 9. Referencias

- Documentación del paquete `camera` (pub.dev) y de `video_player`.
- Documentación de Flutter: *Texture widget*, *AppLifecycleState*, *ImageCache*.
- Zaccagnino, C. (2020). *Programming Flutter: Native, Cross-Platform Apps the Easy Way*. Pragmatic Programmers. Basado conceptualmente en el enfoque de la bibliografía indicada.
