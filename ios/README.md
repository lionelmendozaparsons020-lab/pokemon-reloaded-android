# Reloaded iOS — prototipo experimental

Adaptación nativa del motor OpenGMK de este repositorio para iPhone/iPad ARM64 con iOS 18 o posterior. El objetivo inicial es el iPhone 16 Pro. No es una conversión de APK: comparte el intérprete de GameMaker 8 con la versión Android y utiliza una aplicación UIKit, gráficos OpenGL ES 3 y audio RemoteIO propios de iOS.

**Estado: experimental.** Las pruebas del simulador comprueban el renderizado y la cola de entrada del motor. No sustituyen una prueba de Pokémon Reloaded completo en un iPhone real. La compatibilidad con todas las versiones del juego, sus DLL, las partidas y el rendimiento todavía debe comprobarse en el dispositivo.

## Contenido

- Importación de un ZIP con el ejecutable de Reloaded y su carpeta `data` juntos; puede haber una carpeta contenedora.
- Cruceta con diagonales, botones táctiles, panel de teclas adicionales, teclado para nombres y puntero con clic izquierdo/derecho.
- Pausa del renderizado y del audio al pasar a segundo plano.
- Registro exportable y acceso a las carpetas del juego desde Archivos.
- Compilación del simulador y del IPA ARM64 en GitHub Actions.

El instalador no incluye el ejecutable ni los recursos originales de Pokémon Reloaded. Se importan por separado. Cada importación crea una carpeta nueva y conserva las partidas de importaciones anteriores; no migra partidas automáticamente.

## Instalar desde Windows

1. Descargar el artefacto `Reloaded-iOS-experimental` de una ejecución **exitosa** de [Build iOS](https://github.com/lionelmendozaparsons020-lab/pokemon-reloaded-android/actions/workflows/build-ios.yml) en la rama `ios/iphone16-pro-prototype`.
2. Extraer el ZIP del artefacto. El instalador es `device/Reloaded-iOS-0.1.0-unsigned.ipa`. El archivo es **sin firmar** y no se instala simplemente tocándolo en Archivos.
3. Configurar SideStore siguiendo su [guía oficial](https://docs.sidestore.io/docs/installation/prerequisites). La PC Windows sirve para la configuración inicial y el iPhone firma la aplicación con la cuenta propia del usuario. Seguir los requisitos y los límites vigentes de SideStore y Apple.
4. Instalar el IPA mediante SideStore y abrir Reloaded iOS.
5. Elegir **Importar ZIP del juego**, seleccionar el ZIP completo y mantener la aplicación abierta durante la extracción. Pulsar **Jugar** al terminar.

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

La compilación del dispositivo genera `ios/out/device/Reloaded-iOS-0.1.0-unsigned.ipa` y su SHA-256. No utiliza certificados, credenciales Apple ni perfiles de distribución. El usuario debe firmar el IPA para su dispositivo.

Las pruebas de importación comprueban rutas peligrosas, archivos que no contienen un juego y conservación de un destino existente. La prueba del simulador crea el contexto ES3, dibuja un rectángulo verde, lee un píxel de vuelta, verifica eventos de tecla y texto, y comprueba que RemoteIO recibe muestras PCM del mezclador. Guarda una captura, el registro y el resultado en `ios/out/verification`. El ensayo de audio no verifica el altavoz físico ni los recursos sonoros del juego.

## Prueba pendiente en el iPhone

Importar el juego completo y verificar arranque, menús, movimiento y diagonales, combate, sonido/MIDI, escritura de nombres, guardado y carga, y segundo plano/reanudación. Si falla, guardar el registro y anotar la versión del juego y de iOS. No se ha verificado soporte de mandos físicos ni edición de la distribución de controles.

## Código y licencia

El motor conserva la licencia GPL-2.0-only y los avisos del proyecto OpenGMK y de la adaptación Android de Klisee. El código de esta adaptación está en la misma rama que produce el IPA. `App.m` implementa la interfaz nativa; `Bridge.h` define la ABI; `ios_main.rs`, `render/opengl/eagl.rs`, `game/audio/ios.rs` y `vendor/ramen/src/platform/ios.rs` conectan el motor con iOS. El juego y sus recursos se distribuyen por sus autores.
