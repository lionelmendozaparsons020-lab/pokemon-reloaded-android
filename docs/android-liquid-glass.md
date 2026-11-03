# Android · Liquid Glass (v24)

Rediseño nativo en Jetpack Compose de los ajustes, a partir de la rama Android
`mods-catalogos-ids-internos-v23-039` (89e9dd9). No sustituye el motor por una web.

## Comportamiento

- Tema oscuro Liquid Glass por defecto, con tarjetas agrupadas, datos reales de la
  instalación en tres columnas, separadores discretos, iconos y acciones con flechas.
- Cambiar tema permite volver a Material y los colores del sistema. La preferencia
  se aplica al instante y se recuerda entre sesiones y actividades.
- La edición Controles busca actualizaciones en su propio repositorio, sin ofrecer
  APKs del autor original con otro paquete o firma.
- Cerrar y el botón Atrás vuelven a Inicio. Los submenús vuelven a Ajustes.
- Gestionar mods, Mis partidas (perfiles normal/mods), idiomas, controles táctiles,
  mando, Discord, registros y actualizaciones conservan sus destinos existentes.
- FPS y pantalla reúne 30/60/120/sin límite, proporción/rellenar, contador y pantalla
  encendida. Usa las mismas preferencias y `video.conf` que lee el motor.
- Los modos superiores a 30 FPS siguen siendo experimentales. No se promete una
  tasa de cuadros concreta: depende de la pantalla, del motor y del dispositivo.
- Las nuevas etiquetas incluyen traducciones al inglés. Las filas crecen con el
  tamaño de texto y las listas respetan los espacios de navegación del sistema.

## Actualizar conservando datos

La compilación Controles mantiene `com.klisee.reloaded.controles`, usa versionCode
24 y se firma con la clave del proyecto configurada en GitHub Actions. El proceso
comprueba que su certificado SHA-256 coincide con el APK V22:
`1ed0f054e3f094cf13819312cbcd7688bf940b6aa1a1eaa10f2fccdc32c04260`.

Instala sobre V22/V23 sin desinstalar. La actualización conserva el almacenamiento
privado de la app. Puedes exportar las partidas desde Mis partidas antes de
actualizar. Una aplicación de otro autor o firmada con otra clave no se actualiza
con este APK.

## Compilar

Se conserva el toolchain del proyecto: Rust 1.99.0, cargo-ndk 3.5.4, NDK
27.2.12479018, Java 17, Gradle 9.4.1, plataforma Android 37.0 y build tools 36.0.0.

Desde `src/OpenGMK`:

```sh
RUSTFLAGS='-C link-arg=-Wl,-z,max-page-size=16384' cargo +1.99.0 ndk -t arm64-v8a --platform 29 build -p gm8emulator --lib --release --locked
```

Desde `android`:

```sh
gradle :app:assembleRelease -PcontrolsBuild=true -PtargetAbi=arm64-v8a
```

La firma sigue el mecanismo existente del proyecto. No hay claves privadas ni
contraseñas en el código fuente. `.github/workflows/android-liquid-glass.yml`
compila, prueba y firma usando los secretos ya configurados en el repositorio.

## Verificación

El workflow ejecuta los tests existentes de controles, gestos, parches y Kotlin.
`SettingsUiTest` ejecuta el lanzador real en un emulador Android 15 y comprueba:

1. Datos de instalación, cambio de tema, Cerrar y persistencia al recrear la app.
2. Selección y persistencia de FPS/proporción/contador, escritura de `video.conf`
   y bloqueo de 120 FPS cuando la pantalla no los admite.
3. Rutas de mods, partidas, controles y mando; cancelar la eliminación conserva
   los archivos. Los cambios de tema/vídeo conservan un archivo de partida testigo.

Las capturas del workflow usan una instalación sintética exclusivamente de test.
No incluyen el juego ni validan el rendimiento durante una partida real.
La prueba de Atrás llama al dispatcher real de la actividad, sin simular el gesto
del sistema; el lanzador Pixel del emulador se detiene para evitar sus avisos de
ANR durante el aprovisionamiento inicial.
