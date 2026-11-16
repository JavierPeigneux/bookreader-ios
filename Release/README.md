# Firma y selección de build

Para usar la cuenta de Xcode al firmar mientras la clave API gestiona la ficha, configurar `FOLISONA_USE_XCODE_ACCOUNT: true` en `Release/local.json`, o ejecutar con `FOLISONA_USE_XCODE_ACCOUNT=1`. Es necesario si la clave de metadatos carece de permiso de certificados de distribución gestionados en la nube. Reutilizar `--archive` tras un fallo de exportación evita incrementar la build otra vez.

# Web actual de soporte

La web pública se publica en https://javierpeigneux.github.io/folisona/ desde el repositorio `JavierPeigneux/folisona`, rama `main`, raíz. Incluye el icono de la app como marca y favicon. Las fuentes se mantienen también en `docs/` de este proyecto; deben sincronizarse con el repositorio web al modificarlas.

Soporte: https://javierpeigneux.github.io/folisona/#support
Privacidad: https://javierpeigneux.github.io/folisona/privacy.html

`store_upload.py` asocia el número exacto de `Release/version.json`, o el indicado con `--build-number`, y espera a que esa build esté VALID. No utiliza una build anterior como sustituta mientras Apple procesa la nueva.

# Versión 1.0 con voces de Apple

La build 1.0 (2) y las capturas previas pertenecen al motor anterior. Antes de enviar a revisión, genera una nueva build con `./scripts/release.sh archive --rebuild`, regenera las capturas y carga las nuevas notas de revisión. La versión comercial permanece en 1.0.

# Publicación de Folisona

## Comandos

Desde la carpeta iOS:

```sh
./scripts/release.sh check
source scripts/xcode_env.sh
xcrun swift scripts/make_icon.swift
./scripts/screenshots.sh
./scripts/release.sh archive
./scripts/release.sh export --archive Release/Archives/Folisona-1.0.1-2.xcarchive
./scripts/release.sh upload --archive Release/Archives/Folisona-1.0.1-2.xcarchive
```

`export --archive …` solicita a Xcode una IPA con firma de distribución App Store, sin subirla ni incrementar la versión. La firma automática gestiona el certificado/perfil compatible del equipo; requiere una cuenta autorizada de Apple Developer. El archivo original puede tener firma de desarrollo: Xcode vuelve a firmar al exportar.

También puedes ejecutar `./scripts/release.sh upload` para incrementar versión, archivar y subir en una sola operación. No envía a revisión ni publica automáticamente: deja la build en App Store Connect para su procesamiento y TestFlight. La carga de textos y capturas se realiza con los scripts de publicación de esta carpeta.

`Release/version.json` es la fuente del contador local. Cada archivo nuevo incrementa el patch y la build, y actualiza los dos proyectos JSON nativos. `--version 1.1.0` permite elegir una versión superior. Se reserva el número antes de compilar; una compilación fallida puede dejar un salto, que es válido. `upload --archive …` reutiliza un archivo sin incrementar otra vez. Un bloqueo impide ejecuciones simultáneas en este checkout. Guarda los cambios de versión en Git antes de cambiar de máquina: el contador local no consulta el historial remoto. Al subir, Xcode puede ajustar la build para evitar duplicados en Apple.

## Configuración inicial de Apple (una vez)

- Cuenta de Apple Developer con permisos de distribución. El 16 de noviembre de 2026 se verificó una exportación App Store con el equipo R8B3FUVAHY y su certificado Apple Distribution gestionado por Apple. No es necesario importar una clave privada de distribución local para este flujo.
- Cuenta añadida en Xcode → Settings → Accounts, acuerdos aceptados y una ficha de app creada en App Store Connect con nombre **Folisona** y bundle ID `com.javierpeigneux.Folisona`.
- El bundle ID se conserva para mantener identidad, firma y bibliotecas de instalaciones existentes. Los nombres visibles, productos, targets, módulos, carpetas y esquemas son Folisona. El remoto GitHub conserva su URL actual; no se ha renombrado el repositorio remoto.
- Si usas otro equipo, define `FOLISONA_TEAM_ID`. Para CI puedes usar `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`. La clave `.p8` debe estar fuera del repositorio.
- Opcionalmente guarda esos cuatro campos en `Release/local.json` (ignorado por Git; puedes copiar `Release/local.example.json`). Si no hay clave API, se usa la cuenta de Xcode. No se almacena ninguna contraseña en los scripts.
- La síntesis usa voces de Apple instaladas en el dispositivo. No necesita modelos externos ni permisos GPU.

No es posible eliminar la inscripción de Apple, los acuerdos ni la autenticación con un script. `check` valida herramientas y recursos locales; no certifica permisos de la cuenta ni aprobación de Apple.

## Icono

Fuente aprobada: `Design/AppIcon/Folisona-master.png`. `scripts/make_icon.swift` exporta PNG RGB sin transparencia en 20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180 y 1024 píxeles a `Release/Icons`, y actualiza el AppIcon de la app. El catálogo moderno usa la imagen universal de 1024 px; Xcode genera las representaciones de dispositivo. No se añaden esquinas redondeadas al archivo.

## Capturas reproducibles

`./scripts/screenshots.sh` captura biblioteca, capítulos y lector en castellano e inglés en iPhone 18 Pro, iPad Pro de 13 pulgadas e iPhone Duo. Opciones: `--devices iphone ipad` o `--devices duo`.

Se crean simuladores dedicados llamados `Folisona Store …`. La biblioteca ficticia contiene textos originales de demostración, sin datos personales ni contenido de terceros. El código de preparación solo existe en DEBUG, bajo `--store-screenshots`, y utiliza una carpeta independiente. No se simula audio reproducido, progreso de síntesis ni un historial de escucha.

`python3 scripts/check_release_assets.py` comprueba tamaños y ausencia de transparencia en los 13 iconos y las 18 capturas.

Las imágenes se exportan a `Release/Screenshots/{es,en}/{iphone,ipad,duo}` como JPEG sin transparencia y sin redimensionarlas. Los resultados XCTest y logs se conservan en `.build/store-screenshots`. Revisa composición, idioma y tamaños antes de subirlas. La captura Duo corresponde al estado del simulador; no sustituye una validación de todos sus estados de plegado.

Apple exige capturas de iPhone y, para esta app universal, iPad. Consulta las [especificaciones vigentes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). El script falla si no consigue las seis imágenes esperadas por dispositivo.

## Ficha y pasos pendientes

Textos iniciales en `metadata.json`. Antes de enviar a revisión hay que completar URLs reales de soporte y privacidad, clasificación por edad, declaración de privacidad, derechos sobre el contenido, export compliance, precio/territorios y datos de contacto de revisión. No se han inventado esos datos ni se han enviado declaraciones legales.

Se incluyen los avisos MIT de SwiftSoup y ZIPFoundation en la app. Validar las voces de Apple en un iPhone real (pronunciación, interrupciones y pantalla bloqueada). Las capturas del simulador prueban la interfaz, no la síntesis.

Fuentes: [subida de builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), `xcodebuild -help` de Xcode 27.2 para `app-store-connect`, `destination=upload` y `manageAppVersionAndBuildNumber`.

## Ficha bilingüe y capturas de tienda

`metadata.json` es la fuente de los textos; `StoreText/es-ES` y `StoreText/en-US`
contienen versiones listas para pegar. El precio previsto es **Gratis (0)**; este
valor todavía debe aplicarse y verificarse en App Store Connect.

`Screenshots` contiene capturas directas. `StoreScreenshots` contiene las 18
composiciones para subir (tres por idioma y dispositivo), con tipografía y colores
Folisona. Orden: biblioteca gratuita sin anuncios, capítulos, horas de escucha.
Las horas de las capturas son datos ficticios del modo DEBUG y muestran el
componente real de historial. No representan detección automática del sueño.

Regeneración desde la carpeta iOS:

```sh
./scripts/screenshots.sh
swift scripts/store_artwork.swift
python3 scripts/check_release_assets.py
```

### Estado de la carga del 16 de noviembre de 2026

Se intentó cargar `.build/Folisona-final.xcarchive`. Apple respondió:
`App record with bundle identifier "com.javierpeigneux.Bookreader" not found on App Store Connect`.
La build **no está subida**. La firma de distribución ya se verificó anteriormente.
Crear primero la ficha iOS con nombre Folisona, idioma principal es-ES,
Bundle ID `com.javierpeigneux.Folisona` y SKU `folisona-ios`.
El archive anterior conserva el identificador antiguo y ya no sirve para publicar Folisona. Después de crear la ficha, genera y sube una nueva versión:

```sh
./scripts/release.sh upload
```

La sesión de Xcode sirve para cargar la build. Para automatizar la ficha hace
falta acceso a App Store Connect (navegador o API); actualmente no hay clave API
configurada. No hay textos ni capturas cargados remotamente todavía.
Antes de revisión también faltan URLs públicas de soporte/privacidad, contacto
de revisión, clasificación por edades y declaración de privacidad. No inventar
estos valores ni confundir material local preparado con publicación realizada.

### IPA con la identidad nueva

Archive actual: `.build/Folisona-bundle-id.xcarchive` (1.0.0, build 1).
IPA firmada para distribución: `Release/Exports/Folisona-bundle-id/Folisona.ipa`.
Identificador verificado: `com.javierpeigneux.Folisona`. Tras crear la ficha con
ese identificador, puedes subir este archive sin incrementar la versión:

```sh
./scripts/release.sh upload --archive .build/Folisona-bundle-id.xcarchive
```

## Publicación completa automatizada (app 6835442830)

```sh
./scripts/publish.sh --version 1.0
```

El comando verifica acceso API, recorre biblioteca → capítulos → lector mediante
XCUITest en iPhone 18 Pro, 18 Pro Max, Air, 17e, Duo e iPad Pro 13, en español e
inglés. Exporta 36 capturas reales, genera las composiciones de tienda y comprueba
sus dimensiones. Construye la versión 1.0 incrementando solo el build; carga la
build mediante Xcode y después sube los textos e imágenes. Lee de nuevo los
metadatos, espera que las imágenes estén COMPLETE, comprueba su orden y asocia
la build válida más reciente de esa versión. No envía a revisión ni publica.

La API requiere una clave de equipo App Store Connect con acceso a la app y rol
App Manager. Guardar el .p8 fuera del repositorio y completar `Release/local.json`
(ignorado por Git) siguiendo `local.example.json`: ASC_KEY_PATH, ASC_KEY_ID y
ASC_ISSUER_ID. No pegar la clave privada en chats ni subirla a Git. La sesión de
Xcode permite subir binarios, pero no sustituye esta autenticación de la API.
El script instala PyJWT/cryptography en `.build/publish-venv` si falta el entorno.

Apple recibe una serie por tamaño de pantalla: Pro Max, Pro, 17e, Duo e iPad.
Air comparte categoría con Pro Max y se captura para revisión visual, evitando
subir tarjetas duplicadas a la misma categoría. Todas las capturas se guardan.

Para reanudar solo textos/capturas tras una subida de binario correcta:

```sh
./scripts/publish.sh --version 1.0 --metadata-only --skip-captures
```

Para reutilizar un archive ya construido (su Bundle ID y versión se verifican):

```sh
./scripts/publish.sh --version 1.0 --archive Release/Archives/Folisona-1.0-2.xcarchive --skip-captures
```

Imágenes idénticas se reutilizan por checksum. Si hay imágenes diferentes en las
categorías afectadas, el comando se detiene salvo que se pase
`--replace-screenshots`. No altera otras versiones/categorías. Una ejecución
parcial puede repetirse; el binario no debe volver a subirse si ya se aceptó:
utilizar `--metadata-only`. Informe remoto: `Release/store-upload-result.json`,
que solo se escribe tras verificar imágenes, textos y asociación de build.

La carga de fichas utiliza endpoints appScreenshotSets/appScreenshots todavía
documentados por Apple pero marcados como deprecated a favor de Asset Library.
Sin credenciales no es posible probar su aceptación real en esta cuenta. No
confundir pruebas locales con confirmación remota. Precio 0, política de
privacidad, soporte y datos de revisión siguen requiriendo completar la ficha.

**Última carga realizada:** Apple confirmó `Upload succeeded` para **1.0 (2)**.
Log local `/tmp/folisona-upload-1.0.log`. Advertencia no bloqueante: dSYM del
framework precompilado ESpeakNG ausente. El procesamiento posterior y la ficha
no se han verificado remotamente todavía. Para continuar cuando haya clave API,
usar `--metadata-only --skip-captures`, sin volver a subir el mismo binario.

### API configurada · 16 noviembre 2026

Acceso API aprobado y clave de equipo `Folisona release automation` creada con
rol App Manager. La clave privada permanece fuera del repositorio, en
`~/.appstoreconnect/private_keys/`, con permisos 600. `Release/local.json`
contiene su ruta e identificadores, también con permisos 600 e ignorado por Git.
No se debe incluir el archivo .p8 en el repositorio.

Reanudar la ficha sin reconstruir ni volver a subir la build:

```sh
./scripts/publish.sh --version 1.0 --metadata-only --skip-captures
```

El script reutiliza las capturas idénticas ya cargadas. Tras crear una
localización de versión, consulta de nuevo las localizaciones de App Information
porque Apple puede crearlas automáticamente. Si el idioma principal existente
es en-GB, completa también esa ficha con el material inglés preparado para en-US.
El informe `store-upload-result.json` acredita solo la última ejecución completa.

## Header de la ficha

Arte compartido sin texto para es-ES, en-US y en-GB en
`StoreHeaders/folisona-header.png` (PNG RGB, 3840 × 1646). Fuente y prompt en
`../Design/StoreHeaders`. Generado con la herramienta integrada de imágenes,
con el icono aprobado como referencia; exportación dimensional mediante sips.
El motivo central permanece dentro del área segura de 1646 × 661.

Carga independiente por API:

```sh
.build/publish-venv/bin/python scripts/store_headers.py --version 1.0
```

`publish.sh` también ejecuta este paso cuando existe el PNG. El script consulta
las especificaciones actuales, reutiliza el recurso por una referencia derivada
del SHA-256 y verifica las asignaciones a cada idioma. No reemplaza otro header
existente ni envía a revisión. Informe: `header-upload-result.json`. El estado
ACTIVE de una asignación no significa publicación: la imagen continúa en
PREPARE_FOR_SUBMISSION hasta pasar por revisión.

Fuentes: [especificaciones](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications),
[subida de imágenes](https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets),
[asignaciones](https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces).

## Clasificación por edades

Respuestas de la app actual en `age-rating.json`, aplicadas y verificadas con
`.build/publish-venv/bin/python scripts/store_age_rating.py`. Apple calculó 4+.
Parental Controls = No declara que no existen filtros o restricciones parentales
propios en Folisona; no desactiva controles del sistema. Este comando es separado
de publish.sh: revisar las respuestas cuando cambien funciones o contenido.

## Web de soporte y privacidad (16/11/2026)

- Web pública bilingüe: https://javierpeigneux.github.io/bookreader-ios/
- Soporte: https://javierpeigneux.github.io/bookreader-ios/#support
- Política: https://javierpeigneux.github.io/bookreader-ios/privacy.html
- GitHub Pages publica automáticamente `main:/docs`; commit inicial `5e1daf72520507b6999278c84172b1998c9e467f`.
- Fuente local en `docs/`. Publicar solo los archivos previstos; el árbol de trabajo contiene otros cambios de la app sin publicar.
- Sin dependencias web ni servicios de analítica. Selector ES/EN persistido en localStorage.
- Ejecutar `.build/publish-venv/bin/python scripts/store_review.py` para sincronizar soporte, privacidad, copyright y contacto privado de revisión. El contacto se lee de `Release/local.json` (ignorado, 0600). No envía a revisión.
- La etiqueta de privacidad se prepara/publica aparte en App Store Connect.
- Derechos de contenido pendientes: consultar `Release/license-audit.json` antes de confirmar la declaración. La licencia Apache del modelo/voces no resuelve las obligaciones GPLv3 de eSpeak, incluido en el archivo 1.0 (2).
