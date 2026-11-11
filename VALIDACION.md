# Validación · 11 de noviembre de 2026

## Memoria durante síntesis

- Reproducción del consumo elevado en el harness Mac con el mismo servicio Swift: tres síntesis de un texto de 350 caracteres. Antes: caché MLX final 5.680.749.737 bytes y pico de footprint del proceso 6.096.783.472 bytes (6,10 GB). No son medidas del iPhone ni se confunde footprint con RSS.
- Corrección: caché MLX de 20 MiB, umbral de asignación de 1 GiB (no es un tope absoluto), limpieza entre inferencias y unidades de hasta 96 caracteres dentro de cada bloque ya guardado. WAV escrito por partes y archivo parcial eliminado si hay error/cancelación. Ante memoria baja de iOS: cancelación y liberación del motor/voces/caché al salir de la operación actual.
- Misma comparación tras el cambio: pico de footprint 1.250.739.352 bytes (1,25 GB), caché final 0 bytes. Tres generaciones consecutivas correctas; audio de 20,8 s con señal no silenciosa. La segmentación cambia ligeramente la duración/prosodia respecto a los 20,1 s originales.
- Entrada diez veces más larga: 208,9 s de audio; footprint máximo 1.245.545.648 bytes en Release. Con Swift `-Onone` y Metal API Validation activado: 1.309.705.392 bytes (1,31 GB), pico MLX activo 1.196.523.388 bytes, RMS 1447,87. Tras `releaseResources()`: MLX activo 76 bytes, caché 0. Esto es un ensayo con Swift sin optimizar, no una medición del binario Debug en iPhone.
- Registros y textos reproducibles en `.build/validation/memory/`. El harness acepta ruta WAV, ruta TXT opcional y número de repeticiones opcional.
- Compilación Release iPhone correcta. 14 pruebas funcionales superadas y 1 de síntesis física omitida en Duo, `.build/Memory-Regression.xcresult`. Incluye límites de entrada para libros ya importados, conservación del texto, palabras largas, cancelación y reproducción progresiva.
- Pendiente: confirmar footprint, calidad de las uniones y estabilidad prolongada en iPhone físico. No se ha repetido la instalación fallida en esta iteración.

## Sesión de audio asíncrona

- Eliminadas las llamadas síncronas a `AVAudioSession.setActive`. Activación y desactivación usan las APIs con completion de iOS 27, con una cola compartida para ordenar el cierre de un lector y la activación del siguiente.
- Configuración de categoría y preparación de `AVAudioPlayer` fuera del hilo principal. La preparación se repite al reanudar; una activación cancelada no inicia reproducción tardía.
- Tres pruebas en Duo / iOS 27.2 superadas: reproducción antes de terminar la anticipación, avance ordenado entre capítulos y cierre durante activación seguido de apertura/pausa/reanudación. Resultado `.build/Async-AudioSession-Final.xcresult`. Sin mensajes `AVAudioSession Hang Risk` ni `UI unresponsiveness` en el registro de esa ejecución.
- Esta comprobación del aviso se realizó en simulador; no se reinstaló la app en iPhone físico en esta iteración.

## Capítulos, cola progresiva y corrección de Metal

- EPUB: límites de capítulo persistidos con identidad independiente del título, orden del spine y división por encabezados principales dentro del mismo XHTML. PDF: índice con destinos de página; sin índice, una entrada por página. Los libros antiguos siguen cargando; hay que reimportarlos para obtener los nuevos límites.
- Lista de capítulos al abrir EPUB/PDF, selección, indicador de audio en caché por voz y vista del capítulo actual. Comprobación visual en Duo cerrado con datos de prueba de dos capítulos: apertura de la lista y salto al segundo capítulo correctos. La importación real se comprueba por separado con fixtures EPUB y PDF.
- Reproducción desde el primer fragmento disponible, con un solo fragmento de anticipación. Prueba de cola con WAV de prueba: comienza antes de que termine el siguiente, no solicita el libro entero y una selección cancela el trabajo pendiente. No se presenta ese WAV como síntesis Kokoro.
- Simulador Duo / iOS 27.2: 11 pruebas funcionales y 2 de interfaz superadas; 1 síntesis física omitida. Resultado `.build/Chapters-Duo272-verified.xcresult`. Prueba adicional de autoavance completo entre tres capítulos: superada, `.build/Chapters-Autoplay.xcresult` (14 pruebas superadas en total).
- MLX 0.30.2 local en `Vendor/mlx-swift`, con backport de la corrección oficial https://github.com/ml-explore/mlx/pull/4622 para `set_vector_bytes` vacío. Se conserva la versión exigida por Kokoro y no se desactiva Metal API Validation. SwiftPM muestra una advertencia por la identidad local que sustituye a la dependencia remota transitiva; esta versión resuelve y compila la copia local.
- Compilación Release para iPhone con el MLX local completada y firma verificada. La prueba de síntesis en iPhone no llegó a ejecutarse: instalación sin progreso durante 324 segundos; se interrumpió el test. La instancia previa de Bookreader se cerró antes del segundo intento de instalación directa. `devicectl device install app --timeout 120` también terminó por timeout. El dispositivo figuraba conectado por cable y desbloqueado; no se afirma instalación ni síntesis en iPhone completadas.
- Harness Mac con `MTL_DEBUG_LAYER=1 METAL_DEVICE_WRAPPER_TYPE=1`: registro «Metal API Validation Enabled», regresión de gather escalar correcta y síntesis Dora correcta. WAV `.build/validation/Dora-metal-validation.wav`: 5,35 s, 24 kHz, PCM16 mono, RMS 1377,93, pico 11821; generación 5,46 s. No es un benchmark del iPhone. La frase corta con el binario anterior también pasó en este Mac: no se afirma haber reproducido aquí el fallo específico observado en el dispositivo.

## Localización inglés y castellano

- Catálogos `Localizable.xcstrings` e `InfoPlist.xcstrings` con 62 claves semánticas estables (por ejemplo, `library.import` y `reader.play`), idiomas `es` y `en` declarados en los proyectos. Interfaz, accesibilidad, voces, estados, errores y plurales localizados; los documentos conservan su contenido.
- Compilación del proyecto principal para iPhone con Kokoro: **BUILD SUCCEEDED** (sin firma).
- Pruebas en Duo / iOS 27.2: 7 funcionales y 2 de interfaz superadas; síntesis física omitida explícitamente. Resultado tras migrar a claves semánticas: `.build/Localization-Keys-Duo272.xcresult`.
- La prueba inglesa fuerza `en_US` y comprueba importación, singular «1 section», lector, estado inicial, etiqueta accesible y error de Kokoro. La prueba castellana fuerza `es_ES` y comprueba lectura, rotación y persistencia.
- La síntesis real en iPhone sigue pendiente; esta validación no cambia ese estado.

## Migración a JSON e iOS 27.2

- Xcode 27.2 RC, build 27B48; SDK iOS 27.2 y Metal Toolchain 27B47.
- Los proyectos principal, de simulador y de comprobación en Mac usan `project.xcproj` generado con la conversión oficial `xcodebuild -convert-project 'Xcode Project'`. No quedan `project.pbxproj` en esos paquetes. Los JSON pasan por el lector/formateador oficial `xcprojformatter`.
- La app y sus tests tienen mínimo iOS 27.2. Los YAML y el generador de simulador se han retirado; las copias previas están en `.build/pre-json`.
- Compilación del proyecto principal con Kokoro y SDK 27.2: **BUILD SUCCEEDED**, sin firma para esta comprobación. No se ha reinstalado esta versión en un iPhone físico.
- Pruebas funcionales en iPhone 18 Pro / iOS 27.2 (24B114): 7 superadas; síntesis de dispositivo omitida explícitamente. Resultado `.build/JSON-iPhone272.xcresult`.
- Prueba de interfaz en iPhone 18 Pro / iOS 27.2: superada tras esperar la estabilización de la geometría durante la rotación. Resultado `.build/JSON-iPhone272-rotation.xcresult`.
- `NavigationSplitView` sustituye la navegación de una sola columna; biblioteca y detalle se adaptan al ancho disponible. El lector tiene ancho de texto limitado, Dynamic Type y controles de al menos 44 puntos para avanzar/retroceder.
- Se instalaron los runtimes iOS 27.2 general (24B114) y específico de Duo (24B91016s). El primero no admite crear un Duo; el segundo sí. La comprobación inicial de Duo en 27.1 se hizo con una copia temporal del proyecto que ya se ha eliminado; no rebajó el mínimo de la app.
- Prueba de interfaz en iPhone Duo / iOS 27.2: superada, incluyendo apertura del lector, rotación y persistencia tras relanzar. Resultado `.build/JSON-Duo272-layout.xcresult`.
- Comprobación visual en DeviceHub con Duo abierto, parcialmente abierto y cerrado: el libro seleccionado se conserva, biblioteca y lector aparecen juntos con ancho amplio y el lector ocupa la vista compacta al cerrar. El selector de voz y el botón de reproducción permanecen visibles. Es una primera adaptación con navegación estándar, sin lógica personalizada para la bisagra.

## Validación de la primera versión (antes de la migración)

## Verificado

- Xcode 27.1 (27A9275), Swift Package Manager, XcodeGen 2.46.0; se instaló Metal Toolchain 27A266a para compilar MLX.
- Proyecto principal `Bookreader.xcodeproj`: compilación para iPhone completada y firmada con el equipo local. KokoroSwift y eSpeak NG están embebidos en `Bookreader.app/Frameworks`.
- Modelo safetensors: 327.115.152 bytes; SHA-256 `4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8`.
- Voces preparadas: `ef_dora`, `em_alex`, `em_santa`, `af_heart`.
- Simulador iPhone Duo / iOS 27.1: 7 pruebas funcionales superadas; 1 prueba de interfaz superada; 1 prueba de síntesis en dispositivo omitida explícitamente. Resultado: `.build/SimulatorTests5.xcresult`.
- Cobertura funcional: TXT/Markdown y tildes, PDF con texto y rechazo de página vacía, EPUB en orden de spine y entidades HTML, rechazo de DRM, UTF-8 inválido/formato no soportado, fragmentación sin pérdida de palabras y persistencia/eliminación.
- La prueba de interfaz abre la biblioteca, importa el ejemplo castellano, abre el lector y comprueba que el libro persiste al relanzar. Capturas exportadas a `.build/screenshots` y revisadas visualmente.
- Generación real en Mac con **el mismo `KokoroService.swift` de iOS**, el fork multilingüe y Dora: archivo `.build/validation/Dora-castellano.wav`, 5,35 segundos, mono, PCM16, 24 kHz, pico 12.114 y RMS 1.378,50. Tiempo de generación inicial aproximado: 5,80 segundos. No es un benchmark del iPhone.

Texto de la prueba: «¡Buenos días! El niño lee un libro en castellano. Mañana iremos a la biblioteca de Valencia.»

## Pendiente

- La instalación/ejecución de pruebas en el iPhone de Javier falló por desconexión de CoreDevice (`IXRemoteErrorDomain`, código 6; `Connection interrupted`). La consulta posterior indica que el dispositivo requiere desbloqueo. No se afirma que la app haya quedado instalada o que Kokoro esté validado en ese iPhone.
- Escucha humana de calidad, pronunciación completa y acento; verificación real de reproducción con pantalla bloqueada e interrupciones.
- Medidas de memoria, temperatura, batería y generación prolongada en dispositivo. Las pruebas de documentos usan fixtures pequeños; todavía no hay una prueba con un libro largo.

## Ajustes de integración

- El port original solo configuraba inglés; se eligió el fork multilingüe y su procesamiento español eSpeak NG.
- El framework binario eSpeak NG requiere iOS 18.2; ese fue el mínimo inicial. La app ahora exige iOS 27.2.
- MLX no enlaza con el simulador de este Xcode (`MTLIOErrorDomain`/`MTLTensorDomain`). `BookreaderSimulator.xcodeproj` usa el mismo código de app sin las dependencias de inferencia; pulsar síntesis muestra un error explicativo, sin audio simulado.
- Se añadió embedding explícito de KokoroSwift, necesario para cargar el framework al ejecutar la app.

## Segundo plano y preparación persistente · 11 de noviembre de 2026

- Compilación Release para dispositivo físico con la integración de BackgroundTasks: correcta (sin firma en esta comprobación).
- Suite de simulador iPhone Duo 27.2: 18 pruebas funcionales y 2 de interfaz pasadas; 1 prueba de Kokoro real omitida porque requiere dispositivo físico. Resultado: `.build/Background-Offline.xcresult`.
- Nuevas pruebas con servicio de audio y concesión de segundo plano controlados: preparar un capítulo sin mover la lectura, restaurar audio persistente, migrar caché antigua, conservar progreso al expirar el permiso y reanudar solo fragmentos pendientes. También comprueban que pausar audio conserva la preparación y que perder permiso detiene la generación sin cortar el audio ya iniciado.
- El permiso GPU real, su expiración por el sistema y la reproducción/generación con pantalla bloqueada quedan pendientes de prueba en iPhone. Los dobles de prueba no validan la ejecución de Metal en segundo plano.

- La firma automática con GPU fue rechazada: el equipo personal «Javier Peigneux» no admite Background GPU Access y su perfil no incluye el entitlement. La capacidad queda optativa mediante `BOOKREADER_GPU_ENTITLEMENTS`; por defecto no se solicita en la firma para permitir instalar con ese equipo.
- Compilación Release final con firma automática del equipo personal y GPU optativa desactivada: **BUILD SUCCEEDED**. Incluye la corrección de cancelación cuando la tarea expira antes de comunicar su concesión. No se ha instalado ni probado esta compilación en el iPhone.
