# Biblioteca, carpetas y límite de importación · 18 noviembre 2026

- Límite de archivo y EPUB expandido: 200 × 1024 × 1024 bytes. Avisos ES/EN actualizados. Se conserva el límite independiente de 2.000.000 de caracteres extraídos; no se ha medido el consumo máximo con un documento real de 200 MB en iPhone físico.
- Duplicados por SHA256 del texto normalizado, calculado fuera del hilo principal: copias renombradas no se guardan de nuevo, conservan historial y ofrecen abrir el original. Documentos distintos con igual nombre siguen admitidos.
- Carpetas persistidas en `Library/Organization/folders.json`, compatibles con bibliotecas existentes. Crear, renombrar, mover, agrupar por arrastre y eliminar carpeta sin borrar documentos. Búsqueda global por título/contenido o limitada a la carpeta abierta.
- 31 pruebas funcionales pasadas en `.build/library-folders-2.xcresult` (la fase UI posterior se interrumpió por esperas de animación del simulador). Incluyen duplicados, historial conservado, migración implícita, persistencia, búsqueda sin acentos, nombres inválidos, fallo de escritura y rechazo por encima de 200 MB.
- Prueba UI de creación, movimiento, renombrado y búsqueda pasada en `.build/library-ui-4.xcresult`. Prueba de arrastre pasada en `.build/library-drag-5.xcresult`, tras ajustar el gesto XCTest a una pulsación de 1,2 s y una pausa sobre el destino. Capturas de carpeta y búsqueda revisadas visualmente. Las animaciones se desactivan solo con un argumento DEBUG de las pruebas; la app normal no cambia.
- Validación en simulador iPhone 18 Pro, iOS 27.2. Estos cambios no se han subido a App Store Connect.

# Campos obligatorios de revisión · 16 noviembre 2026

- Ejecutado `scripts/store_submission_setup.py` sobre la build asociada 1.0 (3), VALID. `usesNonExemptEncryption=false` guardado y releído: CryptoKit se usa para SHA256 de identificadores; no hay implementación criptográfica propia ni de terceros. Añadida `ITSAppUsesNonExemptEncryption=false` al Info.plist para futuras builds; no es necesario reconstruir la build 3 para resolver su declaración remota.
- App Information: categoría primaria BOOKS y `contentRightsDeclaration=USES_THIRD_PARTY_CONTENT` guardadas y releídas. La app muestra archivos importados por el usuario, sin catálogo remoto ni redistribución de libros; recursos de bienvenida originales, voces mediante APIs de Apple y dependencias MIT con avisos completos. El análisis antiguo de licencias de build 2 no describe el binario 3.
- Precio gratuito configurado en la base existente USA, sin fechas de finalización. Comprobados precios manuales y automáticos: 175 entradas territoriales con precio 0. Informe privado local `Release/submission-setup-result.json` excluido de Git.
- Readback con espera por consistencia eventual de Apple; la declaración de exportación ya fijada no se vuelve a escribir (Apple devuelve 409). Info.plist validado con plutil. No se ha intentado enviar a revisión ni se afirma que no puedan aparecer otros requisitos al hacerlo.

# Nueva release con voces de Apple · 16 noviembre 2026

- Carga API final: 45 capturas COMPLETE en es-ES/en-US/en-GB, orden y textos releídos; build 1.0 (3) VALID asociada y verificada en la ficha. Informe local `Release/store-upload-result.json`. No enviado a revisión.

- Regeneradas 36 capturas y sus 36 composiciones ES/EN para iPhone, Pro Max, Air, 17e, iPad y Duo. Doce pruebas UI pasadas en `.build/store-screenshots/20261116-200522`; dimensiones y ausencia de alfa verificadas. Revisados visualmente lector ES y composición EN con voces Mónica/Samantha y controles nuevos.
- Archive 1.0 (3), Bundle ID `com.javierpeigneux.Folisona`, sin frameworks externos de síntesis. La clave API rechazó firma cloud; se reutilizó el mismo archive con la cuenta de Xcode. `Upload succeeded` y `EXPORT SUCCEEDED` en `.build/upload-apple-voices-xcode.log`. API confirmó build 3 VALID, no expirada.
- Configuración local `FOLISONA_USE_XCODE_ACCOUNT=true` permite firmar con Xcode conservando la clave API para metadatos. Quince pruebas de los scripts pasadas. Las credenciales y los archivos de distribución siguen excluidos de Git.

# Web Folisona y URLs de revisión · 16 noviembre 2026

- Creado repositorio público `JavierPeigneux/folisona` exclusivamente para la web. GitHub Pages activado en `main:/`; sitio https://javierpeigneux.github.io/folisona/ publicado, commit `fac573962dcc86de30f088d4b6c3a92485ce67c3`.
- Icono aprobado de la app como marca, favicon y apple-touch-icon. Web ES/EN y privacidad comprobadas por HTTP y comparación de bytes; revisión visual del icono y cambio ES→EN en Chrome.
- `store_review.py` completado: soporte `/folisona/#support` y privacidad `/folisona/privacy.html` releídos en es-ES, en-US y en-GB. Notas de revisión actualizadas al motor de Apple. No enviado a revisión.
- Protegida la asociación de build: `store_upload.py` espera la build exacta, evitando seleccionar la build antigua VALID mientras se procesa la nueva. Seis pruebas del script pasadas.

# Continuidad de reproducción en segundo plano · 16 noviembre 2026

- Causa encontrada en código: la ventana de anticipación exigía primer plano, y abandonar la app cancelaba la generación sin concesión de BGContinuedProcessingTask. Tras consumir los dos fragmentos guardados no se preparaban los siguientes.
- Separada la anticipación para escucha de la preparación explícita de libros. La primera continúa durante la reproducción con UIBackgroundModes audio y sesión playback; no solicita una tarea finita por cada ventana. La preparación explícita conserva concesión/expiración y persistencia. Pausar en segundo plano detiene la anticipación; volver a primer plano permite rellenar la cola pendiente.
- Suite: 27 pruebas pasadas, cero fallos (`.build/BackgroundPlayback.xcresult`). Nueva regresión con seis fragmentos y actividad inyectada: cambia a segundo plano sin permiso de tarea, avanza más allá de la ventana inicial, genera todos en orden y registra escucha del último. Usa WAV de prueba; no demuestra concesión de ejecución de iOS con pantalla bloqueada.
- Build física firmada correcta (`.build/background-phone-build.log`); instalación mediante devicectl confirmada (`.build/background-phone-install.log`) y lanzamiento de com.javierpeigneux.Folisona correcto en el iPhone conectado. No se ha comprobado todavía una escucha prolongada con bloqueo físico ni se ha subido otra build a App Store Connect.

# Carga de audio e interfaz simplificada · 16 noviembre 2026

- Control de reproducción permanente con espera cancelable y estado de audio único. Sin barras, porcentajes ni cronómetros en biblioteca/lector; la preparación explícita mantiene un contador de fragmentos.
- Al escuchar se prepara el fragmento actual y uno de anticipación; se reproduce primero el audio ya guardado. La preparación explícita de capítulo/libro permanece disponible. El avance de la cola amplía la ventana sin preparar el libro entero de golpe.
- Reutilización del sintetizador después de solicitudes correctas, manteniendo motores independientes para operaciones simultáneas/canceladas. Prueba Mac con seis fragmentos iguales: media de los cinco posteriores al primero, 198,3 ms antes y 48,2 ms después. Medida de síntesis, no latencia de reproducción en iPhone ni garantía de rendimiento. Logs `.build/audio-speed-before.log` y `.build/audio-speed-after.log`.
- WAV reales en Mac: duraciones/RMS conservados en español e inglés; cancelación y nueva solicitud correctas (`.build/loading-host.log`).
- Sin voces: pantalla con acción Descargar voces, instrucciones y apertura de Ajustes mediante `UIApplication.openSettingsURLString`. Este destino público abre los ajustes de la app, no la pantalla de descarga. El SDK 27.2 no expone un destino público específico para Voces; no se utilizan esquemas privados. La lista de voces se refresca al volver a primer plano.
- Primera suite de esta mejora: 25 pruebas funcionales y 3 de interfaz correctas, incluyendo abrir Ajustes y regresar; dos pruebas de capturas de tienda omitidas. Suite final también correcta: 25 funcionales y 3 de interfaz pasadas, cero fallos, dos capturas de tienda omitidas (`.build/LoadingClarity-final.xcresult`), tras ajustar el avance de la cola y la persistencia del estado pausado.
- Revisión visual de las pantallas sin voces y de instrucciones; contraste de botones y fondo del lector corregidos. Prueba focalizada de apertura de Ajustes repetida y pasada (`.build/LoadingClarity-settings.xcresult`).
- Compilación Release para iPhone sin firma correcta (`.build/loading-release.log`). No se ha subido una nueva build ni actualizado la ficha de App Store Connect.

# Validación actual · voces de Apple · 16 noviembre 2026

- Respaldo completo del estado anterior publicado y verificado: `44c47de5d45b5a1a5675ed36018e34828bf2dae2`. Árbol remoto idéntico al local: `90e244ba19f79b1933de368e891edfe4b891e9e2`.
- Se sustituye Kokoro por `AppleSpeechService`, con voces instaladas de Apple en español e inglés. Se eliminan Kokoro, eSpeak, Misaki, MLX, MLXUtilsLibrary, swift-numerics, modelos, embeddings, copia vendorizada y entitlement GPU. Los dos `Package.resolved` contienen únicamente SwiftSoup y ZIPFoundation.
- Versión comercial conservada: **1.0**. No se ha archivado ni subido otra build a App Store Connect. La build 1.0 (2) ya subida sigue siendo la anterior.
- Compilación Release para iPhone sin firma: **BUILD SUCCEEDED**, `.build/apple-device-final.log`. Binario aproximadamente 5,8 MB; inspección del bundle sin frameworks ni recursos del motor anterior y con avisos MIT incluidos. No es una estimación del tamaño final de descarga de la App Store.
- Suite final iPhone 18 Pro, simulador iOS 27.2: **23 pruebas funcionales y 2 de interfaz pasadas**, cero fallos. Dos métodos de capturas de tienda omitidos porque requieren el modo específico de generación. Resultado: `.build/AppleSpeech-final.xcresult`.
- Síntesis real de español e inglés en simulador: WAV adjuntos, duración superior a un segundo y muestras con señal. Cancelación seguida de otra generación, ausencia de parciales, voz no instalada y reutilización de audio preparado verificadas.
- Comprobación Mac con los mismos archivos fuente del servicio: castellano 40,918 s, RMS 0,15568; inglés 39,361 s, RMS 0,16158. Cancelación y nueva solicitud correctas. `.build/apple-host-check.log`; reproducible con `./scripts/test_apple_speech.sh`. Estos resultados no son medidas de un iPhone físico.
- 13 pruebas Python de publicación pasadas; `./scripts/release.sh check` correcto sin recursos de modelos.
- Primera pasada de iOS: falló únicamente la prueba antigua que exigía migrar la caché. Se reemplazó por la verificación de reutilización de audio de Apple; la suite completa posterior pasó. No se incorpora migración de audios/voces anteriores, según el alcance de esta primera versión.
- Capturas XCTest revisadas para comprobar selector y controles. El simulador conservaba un libro de bienvenida importado previamente cuyo texto mencionaba Kokoro; el recurso de bienvenida de la app nueva ya menciona las voces de Apple. No se modifica contenido de libros importados.
- Pendiente antes de publicar: prueba física en iPhone de pronunciación, interrupciones, bloqueo y concesión/expiración de la tarea de segundo plano; regenerar capturas de tienda y subir una nueva build 1.0. La nueva tarea es CPU, sin GPU; su ejecución real en segundo plano no queda validada por simulador ni Mac.

---

# Historial anterior a la sustitución del motor

Las comprobaciones siguientes describen versiones anteriores con Kokoro, no la implementación actual.

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
- Compilación Release para iPhone con el MLX local completada y firma verificada. La prueba de síntesis en iPhone no llegó a ejecutarse: instalación sin progreso durante 324 segundos; se interrumpió el test. La instancia previa de Folisona se cerró antes del segundo intento de instalación directa. `devicectl device install app --timeout 120` también terminó por timeout. El dispositivo figuraba conectado por cable y desbloqueado; no se afirma instalación ni síntesis en iPhone completadas.
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
- Proyecto principal `Folisona.xcodeproj`: compilación para iPhone completada y firmada con el equipo local. KokoroSwift y eSpeak NG están embebidos en `Folisona.app/Frameworks`.
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
- MLX no enlaza con el simulador de este Xcode (`MTLIOErrorDomain`/`MTLTensorDomain`). `FolisonaSimulator.xcodeproj` usa el mismo código de app sin las dependencias de inferencia; pulsar síntesis muestra un error explicativo, sin audio simulado.
- Se añadió embedding explícito de KokoroSwift, necesario para cargar el framework al ejecutar la app.

## Segundo plano y preparación persistente · 11 de noviembre de 2026

- Compilación Release para dispositivo físico con la integración de BackgroundTasks: correcta (sin firma en esta comprobación).
- Suite de simulador iPhone Duo 27.2: 18 pruebas funcionales y 2 de interfaz pasadas; 1 prueba de Kokoro real omitida porque requiere dispositivo físico. Resultado: `.build/Background-Offline.xcresult`.
- Nuevas pruebas con servicio de audio y concesión de segundo plano controlados: preparar un capítulo sin mover la lectura, restaurar audio persistente, migrar caché antigua, conservar progreso al expirar el permiso y reanudar solo fragmentos pendientes. También comprueban que pausar audio conserva la preparación y que perder permiso detiene la generación sin cortar el audio ya iniciado.
- El permiso GPU real, su expiración por el sistema y la reproducción/generación con pantalla bloqueada quedan pendientes de prueba en iPhone. Los dobles de prueba no validan la ejecución de Metal en segundo plano.

- La firma automática con GPU fue rechazada: el equipo personal «Javier Peigneux» no admite Background GPU Access y su perfil no incluye el entitlement. La capacidad queda optativa mediante `FOLISONA_GPU_ENTITLEMENTS`; por defecto no se solicita en la firma para permitir instalar con ese equipo.
- Compilación Release final con firma automática del equipo personal y GPU optativa desactivada: **BUILD SUCCEEDED**. Incluye la corrección de cancelación cuando la tarea expira antes de comunicar su concesión. No se ha instalado ni probado esta compilación en el iPhone.

## Etiquetas de horas de escucha · 11 de noviembre de 2026

- Historial persistente de las últimas 30 sesiones, compatible con bibliotecas anteriores. Las marcas se guardan después de iniciar correctamente la reproducción, nunca durante la preparación del audio.
- 19 pruebas funcionales pasadas y una de Kokoro físico omitida (`.build/Listening-History.xcresult`). Incluyen preservación y serialización de sesiones, ausencia de marcas al preparar sin escuchar y recuperación de la posición anterior.
- Las dos pruebas de interfaz pasan: castellano en el resultado anterior e inglés en `.build/Listening-History-UI-Final.xcresult`. Se corrigió la prueba para reconocer el texto del menú como elemento accesible y cerrarlo mediante su opción visible.
- Compilación Release firmada para iPhone correcta. Revisión visual manual en Duo cerrado: etiquetas caption2 compactas, junto al texto y ocultables desde el reloj, con una muestra de historial sintética eliminada tras la comprobación. No equivale a una prueba de síntesis en el dispositivo físico.

## Metal al pasar a segundo plano · 11 de noviembre de 2026

- Causa identificada: cancelar la tarea Swift entre fragmentos no detiene los envíos de una llamada síncrona de Kokoro ya en curso. La reacción previa a `scenePhase.background` llegaba después de perder acceso a la GPU.
- Bloqueo nativo en el único punto de envío de command buffers del backend Metal vendorizado. Al cerrar el bloqueo no se admiten nuevos envíos y los previos ya están programados (`waitUntilScheduled`). El worker espera hasta volver a disponer de permiso; no se descartan buffers ni se silencian excepciones de Metal.
- Observadores síncronos de `UIApplication.willResignActiveNotification` y `didBecomeActiveNotification`, instalados antes de la primera escena. El permiso GPU válido permite seguir en segundo plano; la expiración revoca el acceso antes de despachar cambios a MainActor, rechaza concesiones tardías y completa la tarea del sistema sin esperar a un worker bloqueado.
- Suite Duo: 20 pruebas funcionales y 2 de interfaz pasadas, 1 de Kokoro físico omitida (`.build/GPU-Lifecycle.xcresult`). Dos pruebas focalizadas repetidas tras el ajuste final de expiración: correctas (`.build/GPU-Lifecycle-Final.xcresult`).
- Harness Mac con validación Metal activada: `METAL_SUBMISSION_GATE_OK`, evaluación detenida con el bloqueo cerrado y resultado correcto al reabrirlo; regresión de scalar gather correcta. Kokoro real: WAV de 5,35 s, 24 kHz mono, RMS 1377,91; generación 0,823 s y liberación de memoria MLX hasta 76 bytes activos. Esto valida el mecanismo nativo, no los permisos de segundo plano del iPhone.
- Compilación Release firmada final para iPhone: correcta. La confirmación del fallo original requiere bloquear la pantalla durante síntesis en un dispositivo físico.
- Intento de instalación física con CoreDevice: agotó el timeout de 60 segundos. No se afirma instalación ni validación de bloqueo de pantalla en el iPhone.

## Progreso de preparación · 11 de noviembre de 2026

- Barra con porcentaje y avance por unidad de síntesis dentro de cada fragmento. Estimación restante basada en tiempo monotónico y trabajo nuevo; el audio precargado se cuenta en el progreso pero se excluye de la medición de velocidad. Las estimaciones se actualizan con cada avance y son aproximadas: los fragmentos pueden tener costes diferentes.
- 21 pruebas funcionales pasadas y 1 de síntesis física omitida. Incluye la exclusión de caché del cálculo, progreso parcial, finalización y ausencia de estimaciones sin muestras nuevas.

## Paleta Folio · 16 de noviembre de 2026

- Colores centralizados en FolioPalette y Assets.xcassets: verde bosque, papel marfil, superficies crema, tinta oscura y salvia para destacados. Aplicados a biblioteca, lector, lista de capítulos, etiquetas y controles.
- Contraste calculado sobre colores opacos: tinta/papel 12,67:1; secundario/papel 5,69:1; secundario/salvia 5,16:1; crema/verde 11,85:1.
- Compilación Release firmada para iPhone correcta. Pruebas de interfaz castellano e inglés pasadas; repetida la prueba castellana con la referencia final al color de acento (`.build/Folio-Colors-Final.xcresult`). Capturas finales de biblioteca y lector revisadas visualmente en `.build/validation/folio/`.

## Folisona y preparación de App Store · 16 de noviembre de 2026

- Renombrados app, carpetas, módulos, targets, esquemas y proyectos JSON a Folisona; actualizado el harness y los scripts. Nombre visible mediante clave `app.name` y catálogo InfoPlist. Se conserva `com.javierpeigneux.Bookreader` como identidad de instalación y prefijo de tareas para mantener continuidad de datos y firma.
- Icono Folio aprobado instalado como AppIcon. Exportados y comprobados 13 tamaños RGB sin alfa (20–1024 px).
- Build Release y archive finales completados. Archivo `.build/Folisona-final.xcarchive`, versión 1.0.0 (1), firma Apple Development del equipo R8B3FUVAHY verificada con `codesign --verify --deep --strict`. No es una exportación firmada para App Store y no se ha subido a Apple.
- Seis pruebas de capturas superadas (ES/EN en iPhone 18 Pro, iPad Pro 13 y Duo). Resultado `.build/store-screenshots/20261116-130155/`. Exportadas 18 imágenes JPEG sin alfa: iPhone 1206×2622, iPad 2064×2752, Duo exterior 1398×2034. Revisión visual de biblioteca, capítulos y lector; no valida la síntesis real ni todos los estados de plegado de Duo.
- Biblioteca de demostración original y aislada bajo DEBUG. Comprobado que `FolisonaScreenshotLibrary` no aparece en el ejecutable Release. El aviso exclusivo del simulador se oculta únicamente en el modo de capturas; no se simula reproducción.
- `scripts/release.sh check` correcto. Cinco pruebas de `scripts/test_release.py` pasadas: incremento, fallo de compilación, subida de archivo existente, rechazo de versiones inválidas y rechazo de proyecto mal formado. Subida real no ejecutada: requiere cuenta/firma de distribución y ficha App Store Connect.
- Metadatos ES/EN preparados y límites de subtítulo, texto promocional y palabras clave comprobados. Soporte, política de privacidad y declaraciones de App Store pendientes de completar con datos reales.
- No se ha confirmado la disponibilidad registral del nombre. Alcance de la búsqueda pública y bloqueos en `Release/NAME-REVIEW.md`.
- Regresión funcional: primera ejecución con un fallo de temporización en `testClosingDuringActivationDoesNotRestartOldReader` durante el arranque de audio del simulador. Repetida la suite completa sin otras capturas en ejecución y sin modificar el test: 21 pruebas pasadas, una de Kokoro físico omitida, cero fallos (`.build/Folisona-regression-retry.xcresult`). Se conserva el resultado fallido inicial; el reintento no demuestra ausencia de intermitencia en el arranque de audio.

## Firma de distribución · 16 de noviembre de 2026

- Ejecutado `./scripts/release.sh export --archive .build/Folisona-final.xcarchive` con `app-store-connect`, destino local y aprovisionamiento automático: **EXPORT SUCCEEDED**.
- El equipo R8B3FUVAHY sí dispone actualmente de firma Apple Distribution gestionada por Apple. La limitación anterior del equipo personal no describe su estado actual. La ausencia de identidad de distribución en el llavero local no impedía esta exportación.
- IPA exportada a `Release/Exports/Folisona-final/Folisona.ipa`, versión 1.0.0 (1). No se ha subido a App Store Connect ni enviado a revisión.
- Añadido comando `export` al script: firma de distribución local, sin subir y sin incrementar versión al utilizar `--archive`. Seis pruebas del script superadas, incluida esa separación entre exportación y subida.
- IPA extraída y firma verificada con `codesign --verify --deep --strict`: autoridad Apple Distribution de Javier Peigneux d'Egmont Benito, equipo R8B3FUVAHY. Perfil `iOS Team Store Provisioning Profile: com.javierpeigneux.Bookreader`, `get-task-allow=false`, sin lista de dispositivos ni distribución enterprise; caducidad 16 de noviembre de 2027.

## Ficha App Store ES/EN y carga (16 noviembre 2026)

- Carga real intentada con la sesión de Xcode y el archive final: Apple la rechazó porque no existe la ficha con Bundle ID `com.javierpeigneux.Bookreader`. No hay build subida ni ficha publicada. No es un fallo de firma.
- Descripciones y textos promocionales ES/EN preparados en `Release/metadata.json` y `Release/StoreText`, con límites de caracteres comprobados. Destacan gratuidad, ausencia de publicidad y horas por fragmento para retomar tras dormirse, sin afirmar detección del sueño.
- Historial ficticio exclusivamente en fixture DEBUG y biblioteca aislada, para capturar las etiquetas reales. No cambia el comportamiento de Release ni requiere reconstruir el archive ya firmado.
- Script `scripts/store_artwork.swift`: composiciones con capturas reales, colores del icono y tipografía editorial, sin retocar los controles de la app. Contexto CoreGraphics RGB sin transparencia; AppKit no admite aquí el contexto bitmap RGB de tres canales y se sustituyó por este contexto compatible.
- Precio gratuito, URLs de soporte/privacidad y demás declaraciones de la ficha todavía pendientes de configurar en App Store Connect. Ningún valor local se presenta como ajuste remoto verificado.
- Capturas renovadas: seis pruebas UI superadas (ES/EN × iPhone/iPad/Duo), resultados `.build/store-screenshots/20261116-132451/`. 18 composiciones finales regeneradas a partir de esas capturas; tamaños y ausencia de alfa comprobados. Revisión visual de composición en iPhone, iPad y Duo.

## Bundle ID Folisona · 16 noviembre 2026

- Por petición del usuario, la identidad actual pasa a `com.javierpeigneux.Folisona` en ambos proyectos; targets de tests con sufijos Tests/UITests. Actualizados Logger, prefijo de tareas de audio y BGTaskSchedulerPermittedIdentifiers.
- Script de publicación actualizado para aceptar exclusivamente archives con el ID nuevo. Siete pruebas superadas, incluida la regresión que rechaza un archive Bookreader sin exportarlo ni consumir una versión. Info.plist válido y comprobación de espacios del diff correcta.
- Las referencias a Bookreader en entradas anteriores de este documento describen resultados históricos. Los archives/IPAs antiguos conservan ese ID y no sirven para la nueva ficha. El cambio crea una app independiente y no migra automáticamente la biblioteca de la instalación anterior.
- Nuevo archive `.build/Folisona-bundle-id.xcarchive`: ARCHIVE SUCCEEDED. Exportación `app-store-connect` correcta a `Release/Exports/Folisona-bundle-id/Folisona.ipa`. Firma profunda/estricta verificada y perfil de distribución con `R8B3FUVAHY.com.javierpeigneux.Folisona`, sin get-task-allow ni dispositivos registrados. No se ha subido esta IPA.

## Publicación automatizada 1.0 · 16 noviembre 2026

- Destino confirmado por el usuario: App Store Connect app 6835442830, Bundle ID com.javierpeigneux.Folisona.
- `release.py --version 1.0 --rebuild` acepta versión comercial de dos componentes y reserva un build nuevo manteniéndola; 8 pruebas locales superadas. Nueva versión registrada 1.0, build 2.
- `publish.sh` coordina comprobación API, capturas reales en 18 Pro/Pro Max/Air/17e/Duo/iPad, composición, validación, carga de binario y ficha. Opción `--metadata-only --skip-captures` para reanudar sin duplicar binarios ni ejecutar otra vez simuladores.
- `store_upload.py` utiliza JWT ES256 con clave API local, upsert ES/EN, subida por segmentos, checksum, espera COMPLETE y comprobación de orden/textos; asocia la build válida más reciente de esa versión. 4 pruebas locales superadas de reutilización, assets ausentes, procesamiento fallido y credenciales ausentes. Integración real con Apple para metadatos aún no validada por falta de credenciales.
- Ejecutado publish.sh en modo reanudación: detención explícita antes de mutaciones remotas por ausencia de ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID. El navegador/app nativa siguen inaccesibles desde las herramientas de esta sesión. No se extrajeron sesiones/cookies ni claves privadas de Xcode.
- Carga real completada: `Upload succeeded` y `EXPORT SUCCEEDED` en `/tmp/folisona-upload-1.0.log`, versión 1.0 build 2. Apple emitió advertencia no bloqueante por dSYM ausente del framework precompilado ESpeakNG. No se declara que el procesamiento asíncrono haya terminado ni que se haya enviado a revisión.
- Recorrido real completo: 12 pruebas de interfaz superadas (seis dispositivos × dos idiomas), resultados `.build/store-screenshots/20261116-135617`. 36 capturas y 36 composiciones generadas; dimensiones y canal alfa verificados. Revisadas visualmente las nuevas composiciones de Pro Max y 17e. Capturas/textos locales preparados, no cargados a Apple por ausencia de clave API.

## Ficha cargada por API · 16 noviembre 2026

- Acceso API aprobado y clave App Manager configurada fuera del repositorio; archivo privado y configuración local con permisos 600. `Release/local.json` y `.p8` excluidos de Git.
- Ejecución real `./scripts/publish.sh --version 1.0 --metadata-only --skip-captures` finalizada con código 0. Textos de versión, nombre y subtítulo releídos y comparados con el material preparado.
- Verificadas 45 capturas COMPLETE, tres por tamaño (iPhone, Pro Max, 17e, iPad, Duo) y localización (es-ES, en-US, en-GB). Air comparte categoría con Pro Max y no duplica imágenes. en-GB se conserva como idioma principal remoto y usa el texto inglés preparado. Orden de las imágenes comprobado por lectura remota.
- Build procesada 1.0 (2) asociada y releída correctamente. Informe local en `Release/store-upload-result.json`. No se volvió a subir el binario y no se envió a revisión.
- Corregida creación de localizaciones: Apple genera App Information al añadir la localización de versión; ahora se vuelve a consultar antes de crearla, evitando HTTP 409. Cinco pruebas locales superadas, incluida conservación de una traducción británica específica si existe.
- Precio, soporte, privacidad, clasificación por edad y datos de revisión quedan fuera de esta carga de capturas/textos.

## Headers y clasificación · 16 noviembre 2026

- Header generado con image_gen a partir del icono aprobado, sin texto y reutilizado en es-ES/en-US/en-GB. PNG RGB sin alfa, 3840 × 1646. Fuente y prompt en Design/StoreHeaders; exportación en Release/StoreHeaders.
- Carga real por App Asset Library API: imagen PREPARE_FOR_SUBMISSION y tres asignaciones PRODUCT_PAGE_HEADER_ASSET/DEFAULT_PROFILE ACTIVE, leídas de nuevo. Informe header-upload-result.json. No enviado a revisión.
- Nuevo store_headers.py consulta especificaciones de Apple, reutiliza el archivo por referencia SHA-256 y evita sustituir un header distinto. publish.py lo integra automáticamente cuando existe el arte. La reanudación reutilizó el header español y completó los dos ingleses.
- Cuestionario de edades aplicado por API con store_age_rating.py, respuestas documentadas en Release/age-rating.json. Parental Controls = false porque no hay controles propios en la app. No modifica Tiempo de uso de iOS. Resto de capacidades ausentes y frecuencias NONE; sin categoría infantil ni elevación manual de edad. Apple devolvió appStoreAgeRating FOUR_PLUS y Brasil L. Todas las respuestas se verificaron con GET appInfos/{id}/ageRatingDeclaration.


## Fallo de TextToSpeech en iPhone · 16 noviembre 2026

- Debugger de Xcode: proceso Folisona detenido en `EXC_BAD_ACCESS` en `objc_retain`, con llamadas de TextToSpeech en el hilo principal y renderizado de audio activo en otro hilo. Es un fallo real observado, no una deducción a partir de avisos de consola. La traza de Time Profiler no contenía muestras porque el debugger mantenía detenido el proceso.
- Corregido el ciclo de vida de la síntesis: motores y delegados persistentes, frase retenida hasta la finalización nativa y el final de buffers; cancelar descarta el parcial y deja drenar el fragmento acotado, sin detener el renderizador desde un callback. Pool limitado a dos motores con espera asíncrona cancelable. Esto corrige riesgos de vida útil; el stack interno de Apple no demuestra por sí solo la causa exacta.
- Prueba añadida: 12 cambios ES/EN y seis cancelaciones rápidas seguidas de nuevas generaciones. El primer intento detectó motores bloqueados después de stopSpeaking; se eliminó esa interrupción. La siguiente suite pasó 26 pruebas sin fallos (`.build/SpeechLifecycle-regression2.xcresult`). Harness macOS: WAV español e inglés con señal y cancelación/reinicio correctos (`.build/speech-lifecycle-host2.log`).
- Build final de pruebas para iPhone compilada y firmada correctamente (`.build/phone-lifecycle-final.log`). La primera instalación directa mediante devicectl agotó 45 segundos; no se presenta la compilación como validación física del arreglo.
- Verificación del código final: 26 pruebas del simulador pasadas en `.build/SpeechLifecycle-final.xcresult`; harness macOS repetido con audio ES/EN y cancelación/reinicio correctos (`.build/speech-lifecycle-host-final.log`). Segunda instalación directa en iPhone agotó 30 segundos (`.build/phone-install-final.log`), por lo que la corrección sigue pendiente de prueba física.
