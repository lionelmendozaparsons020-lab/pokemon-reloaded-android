# Reloaded iOS 0.3.0

Adaptación nativa del motor OpenGMK de este repositorio para iPhone/iPad ARM64 con iOS 18 o posterior. El objetivo inicial es el iPhone 16 Pro. No es una conversión de APK: comparte el intérprete de GameMaker 8 con la versión Android y utiliza una aplicación UIKit, gráficos OpenGL ES 3 y audio RemoteIO propios de iOS.

**Estado: experimental.** Las pruebas del simulador comprueban el renderizado y la cola de entrada del motor. No sustituyen una prueba de Pokémon Reloaded completo en un iPhone real. La compatibilidad con todas las versiones del juego, sus DLL, las partidas y el rendimiento todavía debe comprobarse en el dispositivo.

## Contenido

- Inicio y ajustes en vertical, con diseño, tipografía y colores basados en Android; el juego y el editor de controles se abren en horizontal.
- Noticias recientes del blog oficial, con imagen, fecha y enlace. La fuente es el blog de Reloaded, independientemente del nombre del ZIP. La última noticia se conserva para leerla sin conexión.
- Importación de un ZIP con el ejecutable de Reloaded y su carpeta `data` juntos, incluso dentro de una carpeta contenedora.
- Modos de dibujo 30 FPS original, 60, 120 y sin límite. Los modos superiores interpolan el dibujo y conservan la velocidad de simulación del juego. No garantizan un rendimiento determinado; la pantalla, iOS y la escena limitan los fotogramas visibles.
- Rellenar toda la pantalla o mantener la proporción original. La opción permanece aplicada aunque el juego intente cambiarla.
- Controles Android V22, multitáctil, tres estilos, opacidad, vibración, animaciones y editor de posiciones/tamaños para ocho contextos.
- Importación/exportación de una ranura o de todas las partidas mediante ZIP, con copia previa de los archivos existentes. Los ZIP completos incluyen `partidas`, `equipos` y `char_custom`; admiten esas carpetas en la raíz o bajo `data`.
- Restauración transaccional: valida y prepara el ZIP antes de sustituir archivos; un registro permite recuperar la copia anterior si la app se interrumpe durante la sustitución.
- Idioma del juego, botón F3, iluminación, mantener la pantalla encendida, teclado para nombres y registros exportables.
- Compilación y verificación de la app y del IPA ARM64 en GitHub Actions.

El instalador no incluye el ejecutable ni los recursos originales de Pokémon Reloaded. Cada importación del juego crea una carpeta nueva y conserva las anteriores; no migra partidas automáticamente. Los respaldos anteriores a una restauración aparecen en **Ajustes → Mis partidas → Copias de seguridad**.

Los selectores de archivos y la hoja para compartir son nativos de iOS. Los mandos físicos, Discord y el catálogo completo de mods de Android no están implementados en esta interfaz.

## Actualizar una instalación existente

Instala el nuevo IPA desde el botón **+** de SideStore usando la misma cuenta con la que firmaste la app anterior. Conserva el identificador `com.lixarx.reloaded.ios`. No desinstales la versión anterior: actualizarla encima mantiene Documents, el juego, las partidas y el diseño de controles guardado. Los nuevos ajustes se aplican la próxima vez que abras el juego.

## Instalar desde Windows

1. Descargar el artefacto `Reloaded-iOS-experimental` de una ejecución **exitosa** de [Build iOS](https://github.com/lionelmendozaparsons020-lab/pokemon-reloaded-android/actions/workflows/build-ios.yml) en la rama `ios/iphone16-pro-prototype`.
2. Extraer el ZIP del artefacto. El instalador es `device/Reloaded-iOS-0.3.0-unsigned.ipa`. El archivo es **sin firmar** y no se instala simplemente tocándolo en Archivos.
3. Configurar SideStore siguiendo su [guía oficial](https://docs.sidestore.io/docs/installation/prerequisites). La PC Windows sirve para la configuración inicial y el iPhone firma la aplicación con la cuenta propia del usuario. Seguir los requisitos y los límites vigentes de SideStore y Apple.
4. Instalar el IPA mediante SideStore y abrir Reloaded iOS.
5. Elegir **Importar** en Inicio, seleccionar el ZIP completo y mantener la aplicación abierta durante la extracción. Pulsar **Jugar** al terminar.

Si hay un cierre, volver a abrir la aplicación y conservar `emulator-previous.log` desde Archivos; el botón **Compartir registro** exporta el registro de la sesión actual. Guardar siempre desde el menú del juego antes de salir. Copiar las partidas a otra ubicación antes de desinstalar la aplicación.

## Compilar y verificar en macOS

Requiere Xcode con los SDK de iOS y simulador, Rust 1.99.0 y las herramientas de línea de comandos seleccionadas con `xcode-select`.

```sh
rustup toolchain install 1.99.0 --profile minimal
rustup default 1.99.0
cargo test --manifest-path ios/archive-tests/Cargo.toml
bash ios/build.sh simulator
bash ios/smoke.sh
bash ios/build.sh device
```

La compilación del dispositivo genera `ios/out/device/Reloaded-iOS-0.3.0-unsigned.ipa` y su SHA-256. No utiliza certificados, credenciales Apple ni perfiles de distribución. El usuario debe firmar el IPA para su dispositivo.

Las pruebas de archivos comprueban importación de juegos, rechazo de rutas peligrosas, conservación de archivos existentes, transferencia de ranuras, exportación/importación de partidas y recuperación de una restauración interrumpida. También se ejecutan las pruebas de regresión de controles Android.

El ensayo del simulador usa datos sintéticos, sin recursos de Pokémon: verifica la lectura de noticias, exportación/importación desde el puente nativo, preferencias de FPS, inicio vertical, presentación horizontal con pantalla completa, retorno vertical y edición persistente de controles. Además comprueba shaders, framebuffer, entrada, audio PCM y el arranque real del motor con dos atlas de texturas. Las capturas, el registro y el resultado se guardan en `ios/out/verification`.

Estas comprobaciones no miden 120 FPS en un iPhone físico ni sustituyen una sesión del juego completo. En el dispositivo conviene comprobar menús, movimiento, combate, sonido/MIDI, nombres, guardado/carga y segundo plano/reanudación con el ZIP utilizado. Si falla, conservar el registro y anotar la versión del juego y de iOS.

## Código y licencia

El motor conserva la licencia GPL-2.0-only y los avisos del proyecto OpenGMK y de la adaptación Android de Klisee. El código de esta adaptación está en la misma rama que produce el IPA. `App.m`, `Launcher.m`, `LauncherSupport.m` y `Settings.m` implementan la interfaz nativa; `Bridge.h` define la ABI; `ios_main.rs`, `render/opengl/eagl.rs`, `game/audio/ios.rs` y `vendor/ramen/src/platform/ios.rs` conectan el motor con iOS. El juego y sus recursos se distribuyen por sus autores.
