# Folisona iOS · versión 1.0

Lector SwiftUI para iOS 27.2 o posterior. Importa EPUB sin DRM, PDF con texto, TXT UTF-8 y Markdown, y los lee con las **voces de Apple instaladas en el dispositivo**. Interfaz en castellano e inglés. No traduce los documentos.

Bundle ID: `com.javierpeigneux.Folisona`.

## Abrir y ejecutar

1. Abre `Folisona.xcodeproj` en Xcode 27.2 o posterior y selecciona el esquema `Folisona`.
2. Selecciona un iPhone/iPad o simulador. Para un dispositivo físico, configura el equipo de firma.
3. Importa un documento desde Archivos o pulsa **Probar con un texto en castellano**.
4. Selecciona una voz de Apple y pulsa **Escuchar**.

No hay modelos que descargar, scripts Python de preparación ni dependencias de síntesis externas. Swift Package Manager resuelve únicamente SwiftSoup 2.8.8 y ZIPFoundation 0.9.20 para importar documentos. Sus avisos MIT completos se distribuyen en `Folisona/Resources/ThirdPartyNotices.txt`.

Los dos proyectos (`Folisona` y `FolisonaSimulator`) comparten el mismo código y motor de voz. Se mantienen en formato JSON nativo de Xcode (`project.xcproj`), sin regenerarlos con XcodeGen. `Package.resolved` fija las dependencias.

```sh
source scripts/xcode_env.sh
./scripts/test.sh
./scripts/test_apple_speech.sh
```

`xcode_env.sh` respeta `DEVELOPER_DIR`; en este equipo selecciona Xcode 27.2 RC sin cambiar la configuración global de Xcode.

## Voces y audio sin conexión

El selector muestra las voces de Apple disponibles en español e inglés, con nombre, variante regional y calidad. La selección inicial es la voz de iOS para español de España. Se pueden descargar otras voces desde Ajustes → Accesibilidad. La disponibilidad y los nombres dependen del dispositivo; no se incluyen voces de proveedores externos ni se solicita acceso a una voz personal.

`AppleSpeechService` utiliza `AVSpeechSynthesizer.write(_:toBufferCallback:)` para escribir WAV por fragmentos. La app empieza a reproducir en cuanto el primero está preparado. Al escuchar, prepara únicamente el fragmento actual y el siguiente, y amplía esa ventana al avanzar. El audio ya guardado se reproduce antes de iniciar más preparación. Se reutiliza un máximo de dos motores, conservando su delegado y la frase hasta recibir tanto el final de los buffers como la finalización de la síntesis. Cancelar descarta el audio y deja terminar el fragmento corto en curso antes de reutilizar el motor. El menú permite preparar un capítulo o todo el libro. El audio se guarda en Application Support, excluido de las copias de seguridad, y se reutiliza para la misma voz. No se envía el texto a un servidor propio.

Una voz no disponible ofrece **Descargar voces**, con instrucciones y un botón para abrir Ajustes. Se utiliza `UIApplication.openSettingsURLString`: abre los ajustes de Folisona, no directamente la pantalla Voces, para la que el SDK no ofrece un destino público. La guía indica volver a la pantalla principal y seguir Accesibilidad → Lectura y voz → Voces. La lista se actualiza al regresar a la app; nunca se cambia silenciosamente de idioma. Se comprueba que el audio no esté vacío ni sea silencioso. Cada solicitud reserva un motor y tiene su archivo temporal; cancelar una preparación elimina el parcial y no afecta a otra solicitud.

La interfaz no utiliza barras de progreso. El control de reproducción permanece visible; mientras espera audio muestra un indicador circular, un mensaje y la acción de cancelar. La preparación explícita muestra un contador de fragmentos guardados y permite detenerla. La reproducción del audio preparado funciona con la pantalla bloqueada. Durante la escucha, la preparación del fragmento siguiente continúa aunque la app esté en segundo plano, como parte de la reproducción de audio. Pausar en segundo plano detiene esa preparación. La preparación explícita de capítulo/libro solicita una tarea finita de segundo plano sin GPU; iOS puede denegarla o finalizarla. En ese caso se conserva el trabajo completado y se reanuda desde la app. Para escuchar sin depender de nuevas generaciones, prepara el libro antes.

Esta primera versión no incluye migración de voces, tareas pendientes ni audios de Kokoro.

## Lectura e historial

Los documentos se dividen en capítulos y fragmentos. Puedes elegir capítulo, saltar entre fragmentos y volver a tu posición de lectura. Las etiquetas horarias registran cuándo empezó a sonar un fragmento; el menú del reloj permite mostrar horas y sesiones anteriores. Tocar una hora vuelve al pasaje correspondiente. No es detección del sueño.

`NavigationSplitView` adapta biblioteca y lector a iPhone, iPad y diferentes anchuras. El texto admite Dynamic Type, selección y orientaciones vertical y horizontal. La paleta de papel marfil y verde bosque se centraliza en `FolioPalette` y el catálogo de colores.

Los textos de interfaz, estados, errores, plurales y accesibilidad viven en `Localizable.xcstrings`. El idioma de interfaz no cambia el idioma del libro ni traduce el contenido.

## Arquitectura

- Models: `Book`, `ReadingBlock`, `ReaderVoice`.
- Views: biblioteca y lector SwiftUI.
- ViewModels: estado, importación, generación, reproducción e historial.
- Coordinator: composición de servicios y navegación.
- Services: importación PDFKit/EPUB/texto, persistencia JSON, audio preparado y síntesis de Apple.

## Validación

`./scripts/test.sh` ejecuta las pruebas funcionales y de interfaz en el simulador. Las pruebas reales de voz guardan WAV adjuntos al resultado XCTest y comprueban señal, cancelación y recuperación. Si faltan voces del sistema, la prueba correspondiente se omite explícitamente.

`./scripts/test_apple_speech.sh` compila en macOS los mismos archivos `Book.swift` y `AppleSpeechService.swift`, genera audio español e inglés y verifica señal y cancelación. No sustituye las pruebas en un iPhone físico. Los resultados y límites de validación están en `VALIDACION.md`.

## Publicación

La versión comercial sigue siendo **1.0**. La build 1.0 (2) subida anteriormente contiene el motor anterior. Para preparar otra build de la misma versión:

```sh
./scripts/release.sh check
./scripts/release.sh archive --rebuild
```

Consulta `Release/README.md` para exportar, subir, regenerar capturas y actualizar la ficha. Crear una nueva build no equivale a enviarla a revisión. Las claves `.p8`, `Release/local.json`, archivos de distribución y datos generados permanecen fuera de Git.
