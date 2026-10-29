# iOS 0.2.0 repair candidate

The user's 0.1.0 log reaches Game::launch, creates OpenGL ES 3, and reports two malformed WAVs before ending without a panic or runtime error. This log alone does not establish whether iOS killed the process for memory pressure, a native fault or stack exhaustion. Do not call the launch issue resolved without a real-device run of the imported 1.9.2.2 game.

Changes:
- Drop the input EXE after decoding, before Game::launch.
- Compose/upload one atlas at a time; free each frame buffer as copied instead of retaining all CPU pixels while allocating every GPU atlas.
- Run the engine on an 8 MiB NSThread; retain the view until the engine returns.
- Record startup stages and physical memory footprint, handle memory-warning logging, share both current and previous logs.
- Enable the original Android 0.3.9/V22 control renderer, exact bundled artwork, joystick, context-specific controls, party/field wheels and box/menu gestures on iOS. The UIKit adapter preserves simultaneous touches.
- Edit touch-layout-v1 positions/sizes by profile; choose appearance, opacity, vibration, render rate, scaling and V22 shader settings. Native UIKit navigation remains an iOS adaptation.
- Keep com.lixarx.reloaded.ios and existing gameFolder/import/save paths. No uninstall or reimport is needed for an update signed with the same Apple account.

The Android V22 APK (SHA256 02982ddd6da383d11599c975c8d03ec3295f22aef846b07f9bb6b9f41cbc7461) was inspected: all packaged control PNGs match this repository. User-selected packs/positions stored on an Android device are not part of an APK and are not copied automatically.

Validation in CI: archive import/save preservation, Android touch regression suite, ES3 pixel readback, audio callbacks, actual Game::launch with an original synthetic fixture (malformed WAV handling, two texture atlases, compiled GML, room initialization and frames), simultaneous joystick/Z down/up events. The synthetic fixture contains no game assets and is not a substitute for testing Pokémon Reloaded on an iPhone.

Not yet ported: Android launcher's mods/catalog screens and normal/mod save-profile selector, Android update service, Discord integration and Android-specific gamepad preferences. Those are not represented as implemented by this repair.
