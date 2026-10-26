package com.klisee.reloaded

import android.content.Context
import java.io.File

/**
 * Bundled Moderno V2 artwork is separate from the original Moderno sprites.
 * It is read by the native engine only when style=modern_v2.
 *
 * The user can still override individual buttons in the Sprites editor:
 * touch-sprites-active takes precedence over these bundled images.
 */
object ModernoV2Sprites {
    private const val DIRECTORY = "moderno-v2"

    /** The names under app/src/main/assets/moderno-v2 match the native engine's expected names. */
    val files = listOf(
        "z.png", "x.png", "c.png", "v.png", "space.png", "o.png",
        "m.png", "e.png", "t.png", "l.png", "p.png", "a.png",
        "n.png", "pkmn.png", "sel_world.png", "escape.png",
        "return.png", "joystick-base.png", "joystick-knob.png",
        "s.png", "b.png", "alpha8.png",
        "world__a.png", "battle__a.png", "battle__e.png", "battle__m.png"
    )

    fun forPreview(assetName: String, id: String, profile: TouchProfile): String {
        val file = if (profile == TouchProfile.WORLD && id == "a") "world__a.png" else assetName
        return "$DIRECTORY/$file"
    }

    fun prepare(context: Context) {
        val dir = File(context.filesDir, DIRECTORY)
        if (!dir.isDirectory && !dir.mkdirs()) return
        for (name in files) {
            // Source asset might not exist in an old APK. The engine safely falls
            // back to Moderno's original artwork rather than losing the button.
            runCatching {
                val imageFile = runCatching { context.assets.open("$DIRECTORY/$name") }
                    .getOrElse { context.assets.open(name) }
                imageFile.use { source ->
                    val target = File(dir, name)
                    val temp = File(dir, "$name.tmp")
                    temp.outputStream().use { destination -> source.copyTo(destination) }
                    if (!temp.renameTo(target)) {
                        temp.copyTo(target, overwrite = true)
                        temp.delete()
                    }
                }
            }
        }
    }
}
