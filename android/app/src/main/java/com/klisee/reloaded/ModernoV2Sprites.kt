package com.klisee.reloaded

import android.content.Context
import java.io.File
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream

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

    /** Keep the user's full-color artwork separate from global TouchSprites overrides. */
    fun forPreviewBytes(context: Context, assetName: String, id: String, profile: TouchProfile): ByteArray? {
        val name = forPreview(assetName, id, profile).substringAfter('/')
        val file = File(File(context.filesDir, DIRECTORY), name)
        if (file.isFile && file.length() in 8..(8L * 1024 * 1024)) return file.readBytes()
        return runCatching { context.assets.open("$DIRECTORY/$name").use { it.readBytes() } }.getOrNull()
    }

    /** Import the exact ZIP supplied by the player. No recoloring, no global overrides. */
    fun importPack(context: Context, uri: Uri): Int {
        val accepted = files.toSet()
        val found = LinkedHashMap<String, ByteArray>()
        val signature = byteArrayOf(-119,80,78,71,13,10,26,10)
        context.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "No se pudo abrir el ZIP." }
            ZipInputStream(input.buffered()).use { zip ->
                var entries = 0
                while (true) {
                    val entry = zip.nextEntry ?: break
                    entries++
                    require(entries <= 100) { "El ZIP tiene demasiados archivos." }
                    if (!entry.isDirectory && entry.name.startsWith("sprites/")) {
                        val inner = entry.name.removePrefix("sprites/")
                        val mapped = when(inner) {
                            "8.png" -> "alpha8.png"
                            "joystick.png" -> "joystick-base.png"
                            else -> inner.replace("/", "__")
                        }
                        if (mapped in accepted) {
                            val bytes = ByteArrayOutputStream()
                            val buf = ByteArray(8192)
                            while (true) {
                                val n = zip.read(buf)
                                if (n < 0) break
                                require(bytes.size() + n <= 8 * 1024 * 1024) { "Sprite demasiado grande: $mapped" }
                                bytes.write(buf,0,n)
                            }
                            val img = bytes.toByteArray()
                            require(img.size > 8 && img.take(8).toByteArray().contentEquals(signature)) {
                                "Sprite PNG inválido: $mapped"
                            }
                            found[mapped] = img
                        }
                    }
                    zip.closeEntry()
                }
            }
        }
        require(found.containsKey("alpha8.png")) { "Falta sprites/8.png para el botón 8." }
        require(found.size >= 12) { "El ZIP no contiene los sprites esperados." }
        val dir = File(context.filesDir, DIRECTORY).apply { mkdirs() }
        for ((name, bytes) in found) {
            val tmp=File(dir,"$name.tmp")
            tmp.writeBytes(bytes)
            check(tmp.renameTo(File(dir,name))) { "No se pudo guardar $name" }
        }
        return found.size
    }

    fun prepare(context: Context) {
        val dir = File(context.filesDir, DIRECTORY)
        if (!dir.isDirectory && !dir.mkdirs()) return
        for (name in files) {
            // Source asset might not exist in an old APK. The engine safely falls
            // back to Moderno's original artwork rather than losing the button.
            runCatching {
                val target = File(dir, name)
                if (target.isFile) return@runCatching
                val imageFile = runCatching { context.assets.open("$DIRECTORY/$name") }
                    .getOrElse { context.assets.open(name) }
                imageFile.use { source ->
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
