# Controles 0.3.9

Integración de v0.3.9 con la rama de controles táctiles personalizada.

- Conserva las novedades del motor, importación, FPS experimentales, puzzle Ruinas y teclas opcionales de 0.3.9.
- Joystick visual con ocho direcciones digitales: activación al 10 % del radio, liberación al 7 % e histéresis angular de 5 grados. El mando físico conserva su zona muerta.
- Animación independiente de la entrada: retorno amortiguado, eje unido a una base fija, sombra, inclinación y ocho indicadores de dirección. Respeta opacidad, tinte y desactivación de animaciones.
- Caja/PC sin los botones Z/X/S/O añadidos por el creador. Conserva selección táctil, arrastre libre y pulsación de un segundo sobre un Pokémon en su casilla. No hay clic derecho mientras se transporta. Datos y mochila conservan joystick/Z/X.
- Mantiene sprites, tecla 8 y distribución personalizada. Las migraciones no sobrescriben posiciones existentes.

La compilación oficial mantiene su identidad. Con `-PcontrolsBuild=true` se genera `com.klisee.reloaded.controles`, versión `0.3.9-controles`, código 20. La clave privada permanece fuera de Git. El workflow entrega un APK sin firma; debe firmarse localmente con la clave Controles antes de instalarse.

Validación: `rustc --edition=2021 --test verification/touch_tests.rs -o /tmp/touch-tests && /tmp/touch-tests --test-threads=1`; `gradle :app:testReleaseUnitTest :app:assembleRelease -Pandroid.onlyEnableUnitTestForTheTestedBuildType=false -PcontrolsBuild=true` después de compilar el motor ARM64. La prueba física de la sensación del joystick requiere el dispositivo.
