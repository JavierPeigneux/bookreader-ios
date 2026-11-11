# Bookreader iOS · primera versión

App SwiftUI independiente del servidor Python, iOS 27.2 o posterior. Importa EPUB sin DRM, PDF con texto, TXT UTF-8 y Markdown. Kokoro se ejecuta localmente con Dora, Alex y Santa en español y Heart en inglés. No traduce los documentos.

## Abrir y ejecutar

1. Abre `Bookreader.xcodeproj` con Xcode 27.2 o posterior.
2. Selecciona el esquema `Bookreader`, tu equipo de firma y un iPhone/iPad físico.
3. Ejecuta e importa un documento desde Archivos o pulsa **Probar con un texto en castellano**.
4. Elige voz y pulsa **Preparar y escuchar**. El primer fragmento empieza a sonar cuando está listo y la app prepara los restantes. El menú de preparación permite guardar un capítulo o el libro completo para escucharlo sin generar más audio. Los fragmentos terminados se conservan y se reutilizan al reintentar.

Los modelos no se incluyen en Git. Desde la raíz del repositorio, prepara un entorno Python 3.11 o posterior y descarga los recursos:

```sh
python3 -m venv .venv
.venv/bin/pip install numpy torch
.venv/bin/python scripts/prepare_resources.py
```

El script necesita NumPy y PyTorch (instalados con el comando anterior). Python solo prepara recursos durante el desarrollo; no se incluye ni ejecuta en iOS. El modelo ocupa unos 327 MB y las cuatro voces unos 2 MB. El script verifica el SHA-256 del modelo y usa revisiones concretas para descargar modelo y voces. Los recursos grandes se excluyen de Git.

Las dependencias se resuelven con Swift Package Manager. `Package.resolved` fija las versiones transitivas. Los tres proyectos usan el formato JSON nativo de Xcode (`project.xcproj` dentro de `.xcodeproj`). Estos JSON son la configuración que se mantiene: edítalos desde Xcode o con `xcrun xcodeproj`. Ya no se regeneran desde YAML/XcodeGen.

Para configurar la herramienta de línea de comandos sin modificar la selección global:

```sh
source scripts/xcode_env.sh
```

El script respeta `DEVELOPER_DIR` si lo has configurado; en esta máquina usa `/Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer` (Xcode 27.2 RC, build 27B48). Si Xcode solicita Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain`.

## Interfaz adaptativa e iPhone Duo

La app usa `NavigationSplitView`: biblioteca y lector pueden coexistir en anchuras amplias y la navegación se contrae a una columna en pantallas compactas. La selección se mantiene al cambiar de tamaño. Se respetan las áreas seguras del sistema, incluidos los controles laterales de Duo; el texto tiene un ancho de lectura limitado y los controles de audio se mantienen accesibles. La tipografía del lector responde a Dynamic Type. Se admiten orientaciones vertical y horizontal.

## Idiomas de la interfaz

La app incluye inglés y castellano mediante `Bookreader/Localizable.xcstrings`, con mensajes de error, estados de audio, accesibilidad y plurales. Las claves son identificadores semánticos estables (`library.import`, `reader.play`, `error.pdf.open`); los textos traducidos viven exclusivamente en los catálogos. Los mensajes con argumentos usan el formato localizado, conservando las reglas de plural. Sigue el idioma preferido del sistema; también se puede elegir su idioma desde los ajustes de iOS para la app. El castellano es el idioma de desarrollo y de respaldo. `InfoPlist.xcstrings` localiza el nombre del tipo de documento.

El idioma de la interfaz no cambia la voz seleccionada ni traduce los libros. El ejemplo incluido sigue siendo un texto en castellano. Los títulos y encabezados guardados con el documento se conservan al cambiar de idioma.

## Arquitectura MVVC

Se interpreta MVVC como Model–View–ViewModel–Coordinator (también conocida como MVVM-C):

- **Models:** `Book`, `ReadingBlock`, `ReaderVoice`; datos Codable sin dependencias de UI.
- **Views:** SwiftUI para biblioteca y lectura; presentan estado y envían acciones.
- **ViewModels:** `LibraryViewModel` y `ReaderViewModel`; importación, estado, generación y reproducción.
- **Coordinator:** `AppCoordinator`; composición de servicios y navegación.
- **Services:** `DocumentImporter` (PDFKit, EPUB ZIP/XML/HTML, texto y Markdown), `LibraryStore` (JSON atómico), `KokoroService` (actor que serializa la inferencia y escribe WAV).

## Lista de capítulos y audio progresivo

Al abrir un EPUB o PDF aparece una lista ordenada y seleccionable. El botón de lista del lector permite volver a ella; muestra cuántos fragmentos tienen audio en la voz elegida. El lector presenta el capítulo seleccionado y continúa con el siguiente durante la reproducción.

- EPUB: conserva el orden del `spine` y separa por el nivel de encabezado principal disponible (`h1`, o `h2` si no hay `h1`) dentro de cada archivo. Un EPUB sin encabezados conserva sus secciones del spine. Los capítulos con títulos iguales mantienen identidades distintas.
- PDF: utiliza las entradas principales del índice con destino de página, recurriendo a sus hijos cuando la entrada es un contenedor sin destino. Sin índice, ofrece una lista por páginas. Los límites son por página; entradas que empiezan en la misma página se agrupan. No se detectan capítulos a partir del aspecto visual del texto.
- Los libros ya importados conservan sus datos y caché. Para obtener los nuevos límites de capítulos de un PDF o EPUB antiguo, vuelve a importar su archivo.

La app prepara desde el fragmento seleccionado hasta el final del libro y empieza a reproducir en cuanto el primero está listo. Cada fragmento se sintetiza internamente en unidades de hasta 96 caracteres, preferentemente separadas por puntuación o espacios, y se escribe por partes al WAV. Esto también se aplica a libros ya importados, sin modificar su posición ni su lista de capítulos. Puede haber pausas si la síntesis tarda más que el audio. La preparación muestra una barra con porcentaje que avanza al completar cada unidad de síntesis, además del número de fragmentos guardados. El tiempo restante es aproximado y se calcula con el trabajo nuevo y el tiempo medido en ese dispositivo; el audio ya guardado no falsea la velocidad. Hasta disponer de una medición se muestra «Calculando tiempo restante…». La pantalla muestra carga del modelo, síntesis o guardado y el tiempo transcurrido, sin inventar porcentajes de inferencia. Se puede cancelar o saltar de capítulo; una operación MLX ya en marcha puede tardar en terminar, pero su resultado no reinicia la reproducción cancelada.

La biblioteca y el fragmento de lectura se guardan en Documents/Library. El audio se guarda en Application Support/PreparedAudio por libro/voz/fragmento, excluido de copias de seguridad y disponible después del primer desbloqueo del dispositivo. La preparación promueve también el audio antiguo de Caches al almacenamiento persistente. La posición persistida es por fragmento, no por segundo. El audio se prepara progresivamente, escribiendo cada fragmento a disco sin acumular el libro en memoria. La reproducción continúa entre fragmentos y configura la sesión de audio y los controles de reproducción/pausa de la pantalla bloqueada.

## Horas de escucha

El menú del reloj permite activar **Mostrar horas de escucha**. Cada fragmento escuchado muestra una cápsula pequeña con la fecha y hora de inicio del audio; preparar o leer visualmente un fragmento no crea una marca. Se puede consultar la última escucha de cada fragmento o elegir una de las últimas 30 sesiones conservadas. Una reapertura del lector, un salto manual o una separación de más de 30 minutos entre inicios de reproducción crea una nueva sesión; una pausa breve conserva la hora original.

Con las etiquetas visibles, tocar una etiqueta o el texto reproduce desde el principio de ese fragmento. La sesión histórica queda seleccionada para no reemplazar sus horas durante la nueva escucha. El menú ofrece **Volver a la posición anterior** después de un salto. Las marcas persisten con el libro; no indican que el usuario estuviera despierto y no recuperan escuchas anteriores a esta versión.

## Preparación y reproducción en segundo plano

El menú de preparación ofrece capítulo actual, libro completo y reanudar. La lista de capítulos también permite preparar uno mediante su menú contextual. Pausar el audio no cancela la preparación; detener la preparación conserva los fragmentos terminados y permite seguir escuchándolos. La tarea pendiente se guarda para reanudarla desde la interfaz después de cerrar la app.

La reproducción utiliza el modo de audio en segundo plano. Para la síntesis con Metal se solicita una tarea finita `BGContinuedProcessingTask` iniciada en primer plano, con recurso GPU y progreso visible para el sistema. El archivo `Bookreader/Bookreader.entitlements` contiene `com.apple.developer.background-tasks.continued-processing.gpu`. Está desactivado por defecto porque el equipo personal configurado no admite esta capacidad. Con un equipo y perfil compatibles, define el ajuste de compilación `BOOKREADER_GPU_ENTITLEMENTS = Bookreader/Bookreader.entitlements` y vuelve a firmar. Con el equipo personal se mantiene la reproducción en segundo plano y la preparación en primer plano. Se comprueba `supportedResources` y la concesión efectiva de la tarea antes de continuar la generación en segundo plano.

Si iOS no concede GPU o interrumpe la tarea, se conserva el progreso y se indica que hay que abrir la app para reanudar. El audio ya preparado puede seguir reproduciéndose. No se mantiene artificialmente la app activa con audio silencioso ni se garantiza generación ilimitada. Para escuchar un libro completo sin depender de la generación en segundo plano, prepáralo antes. El funcionamiento real con pantalla bloqueada y la concesión de GPU requieren comprobación en iPhone; el simulador solo valida los estados mediante dobles de prueba.

## Motor y castellano

Se usa el fork `skywalkerswartz/kokoro-ios-multilingual`, revisión `802f904617231cdb746c3910a21d95f16ba022f1`. Activa eSpeak NG para transformar texto español en fonemas e incorpora `.es`. El modelo y las voces son de Kokoro-82M. Esta integración no exige que el documento esté en inglés. La pronunciación y el acento final dependen de la voz; seleccionar español no garantiza por sí solo un acento peninsular perfecto.

La caché de buffers MLX se limita a 20 MiB y se vacía tras cada unidad de síntesis. El umbral de asignación de MLX se fija en 1 GiB para regular el trabajo pendiente; no es un límite absoluto del proceso. Ante un aviso de memoria de iOS, se cancela la preparación y se liberan modelo, voces y caché cuando termina la operación en curso. La división en unidades pequeñas puede modificar las pausas y la prosodia.

Se incluye una copia local de MLX 0.30.2 con el backport oficial para vectores vacíos en `set_vector_bytes`, causante de la aserción `bytes argument cannot be nil` con validación Metal. Véase `Vendor/README.md`. La validación de Metal permanece habilitada. El backend local también incorpora un bloqueo de envíos GPU sincronizado con las notificaciones de UIKit y la concesión/expiración del permiso de segundo plano.

Para el simulador abre `BookreaderSimulator.xcodeproj`. Comparte los mismos archivos Swift y excluye las dependencias MLX, que fallaron al enlazar con el simulador durante la integración inicial. Permite probar importación, biblioteca y lectura; la síntesis MLX está deshabilitada expresamente porque necesita un dispositivo físico. Nunca se sustituye silenciosamente Kokoro por las voces de Apple.

## Límites de esta versión

- EPUB sin DRM, en orden del `spine`; se omiten las entradas `linear="no"`. No representa la maquetación original, imágenes, tablas ni notas enlazadas.
- PDF con texto extraíble; una página sin texto devuelve un error de OCR. No hay OCR ni reconstrucción de columnas.
- Markdown se convierte a texto por líneas; no es un visor completo de Markdown.
- Hasta 25 MB de entrada, 100 MB expandidos en EPUB y dos millones de caracteres.
- La generación en segundo plano depende del soporte GPU y del permiso temporal concedido por iOS. Sin permiso, se detiene al salir; la cola puede escuchar lo guardado y se detiene si necesita más audio. La cancelación Swift se atiende entre operaciones MLX. Además, un bloqueo nativo detiene nuevos envíos a Metal al perder actividad sin permiso GPU. La operación en curso puede quedar esperando hasta recuperar el primer plano, donde completa su cancelación; el audio ya guardado sigue disponible.
- WAV PCM 24 kHz mono; alrededor de 173 MB/hora. Eliminar un libro elimina también su audio preparado y su caché antigua.
- No hay sincronización, descarga de modelos desde la app, exportación de audiolibro ni publicación en App Store.

## Pruebas

El esquema incluye pruebas de TXT/Markdown con tildes, PDF con texto y escaneado, orden EPUB y DRM, división del texto y persistencia. La prueba `testRealKokoroSpanishOnDevice` genera audio con Dora en dispositivo físico y adjunta un WAV al resultado XCTest; en simulador figura como omitida, no como síntesis validada.

Ejecuta `scripts/test.sh` para las pruebas de simulador (puedes elegir otro dispositivo mediante `READER_DESTINATION`). Para el dispositivo físico utiliza el esquema del proyecto principal en Xcode.

`ValidationHarness/KokoroHostCheck.xcodeproj` es una herramienta de desarrollo para probar en el Mac el mismo servicio Swift, modelo y voces. No es la app iOS ni sustituye la prueba en iPhone. Compila en Release; el ejecutable dentro de la app acepta la ruta del WAV de salida como argumento.

Consulta `VALIDACION.md` para los resultados reales de este checkout.

## Dependencias y licencias

- [Kokoro Swift multilingüe](https://github.com/skywalkerswartz/kokoro-ios-multilingual), derivado del port MIT de mlalma.
- [eSpeak NG Swift multilingüe](https://github.com/skywalkerswartz/eSpeakNGSwift-multilingual), incluye eSpeak NG y sus condiciones GPL.
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), modelo Apache 2.0.
- [MLX Swift](https://github.com/ml-explore/mlx-swift), [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary), [MisakiSwift](https://github.com/mlalma/MisakiSwift), [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), [SwiftSoup](https://github.com/scinfu/SwiftSoup).

Las dependencias conservan sus licencias. Esta es una integración local de desarrollo; la distribución debe contemplar las obligaciones de las dependencias, en particular eSpeak NG.
