package com.klisee.reloaded

import android.content.Context
import android.net.Uri
import android.util.AtomicFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.CRC32
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import java.util.zip.ZipEntry

/**
 * Opt-in access to Pokémon Reloaded's BUILT-IN F3 cheats and local save backups.
 *
 * Important: this class does not modify the proprietary .savc format, invent item IDs, or
 * claim to suppress the game's own anti-cheat. A future save editor must validate the game's
 * actual format/checksums before it can safely change money, items, or Pokémon.
 */
class ModSupport(private val context: Context) {
    private val settings = context.getSharedPreferences("mods", Context.MODE_PRIVATE)
    private val backupsDir: File get() = File(context.filesDir, "mods_backups")
    private val currentProfile: String get() = if (modMode) "mods" else "normal"
    private val savesProfileDir: File get() = File(context.filesDir, "save_modes/$currentProfile")

    var showOfficialF3: Boolean
        get() = settings.getBoolean("officialF3", false)
        set(value) {
            check(settings.edit().putBoolean("officialF3", value).commit()) {
                "No se pudo guardar la preferencia."
            }
            writeRuntimeConfig()
        }

    /** This is read before the next game launch; the current session never switches mode. */
    var modMode: Boolean
        get() = settings.getBoolean("modMode", false)
        set(value) {
            check(!GameSession.active) { "Cerrá el juego antes de cambiar de modo." }
            check(settings.edit().putBoolean("modMode", value).commit()) {
                "No se pudo guardar el modo."
            }
            writeRuntimeConfig()
        }

    /** Loaded by the native touch overlay when starting the game. */
    fun writeRuntimeConfig() {
        val atomic = AtomicFile(File(context.filesDir, "mods.conf"))
        val stream = atomic.startWrite()
        try {
            val f3 = if (showOfficialF3) "1" else "0"
            val mode = if (modMode) "1" else "0"
            stream.write("official_f3=$f3\nmod_mode=$mode\n".toByteArray())
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
    }

    fun backups(): List<File> =
        backupsDir.listFiles()
            ?.filter {
                val prefix = "respaldo_${currentProfile}_"
                val legacy = !modMode && it.name.startsWith("respaldo_") &&
                    !it.name.startsWith("respaldo_mods_")
                it.isFile && it.extension == "zip" && (it.name.startsWith(prefix) || legacy)
            }
            ?.sortedByDescending { it.name }
            .orEmpty()

    /**
     * Take a REAL immutable snapshot of partidas/equipos/char_custom, not a reference to
     * the mutable cache file used by the existing export screen. The temp file is verified
     * before the final rename, so incomplete exports are never presented as backups.
     */
    suspend fun createBackup(repo: GameRepository): Result<File> = withContext(Dispatchers.IO) {
        runCatching {
            check(!GameSession.active) { "Cerrá primero el juego para crear un respaldo consistente." }
            check(repo.status() is GameRepository.Status.Ready) { "Instalá el juego primero." }
            check(backupsDir.isDirectory || backupsDir.mkdirs()) {
                "No se pudo crear la carpeta de respaldos."
            }
            val name = "respaldo_${currentProfile}_" +
                SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date()) + ".zip"
            val finished = File(backupsDir, name)
            val partial = File(backupsDir, name + ".partial")
            try {
                if (savesProfileDir.isDirectory) {
                    writeProfileZip(savesProfileDir, partial)
                } else {
                    check(!modMode) { "Abrí Modo Mods una vez para crear su copia de partidas." }
                    repo.exportSaves().getOrThrow().copyTo(partial, overwrite = false)
                }
                verifyArchive(partial)
                check(partial.renameTo(finished)) { "No se pudo guardar el respaldo." }
                finished
            } finally {
                partial.delete()
            }
        }
    }

    /**
     * Only restores a backup created inside this app's private backup directory. Before
     * overwriting data, preserve the currently installed saves if any exist.
     */
    suspend fun restoreBackup(repo: GameRepository, backup: File): Result<Int> = withContext(Dispatchers.IO) {
        runCatching {
            check(!GameSession.active) { "Cerrá primero el juego antes de restaurar la partida." }
            check(backup.parentFile?.canonicalFile == backupsDir.canonicalFile &&
                backup in backups() && backup.isFile) { "Respaldo no válido." }
            verifyArchive(backup)
            val data = File(context.filesDir, "game/data")
            val currentFiles = listOf("partidas", "equipos", "char_custom").any { folder ->
                val root = if (savesProfileDir.isDirectory) savesProfileDir else data
                File(root, folder).walkTopDown().any { it.isFile }
            }
            if (currentFiles) createBackup(repo).getOrThrow()
            if (savesProfileDir.isDirectory) {
                restoreProfileZip(backup, savesProfileDir)
            } else {
                check(!modMode) { "Abrí Modo Mods una vez para crear sus carpetas." }
                repo.importSaves(Uri.fromFile(backup)).getOrThrow()
            }
        }
    }

    /** A backup always represents the selected profile, not the last one played. */
    private fun writeProfileZip(profile: File, output: File) {
        var count = 0
        ZipOutputStream(output.outputStream().buffered()).use { zip ->
            for (folder in listOf("partidas", "equipos", "char_custom")) {
                val root = File(profile, folder)
                if (!root.isDirectory) continue
                for (file in root.walkTopDown().filter { it.isFile }) {
                    check(file.canonicalPath.startsWith(root.canonicalPath + File.separator))
                    zip.putNextEntry(ZipEntry("$folder/" + file.relativeTo(root).invariantSeparatorsPath))
                    file.inputStream().use { it.copyTo(zip) }
                    zip.closeEntry()
                    count++
                }
            }
        }
        check(count > 0) { "Todavía no hay partidas en este modo." }
    }

    /** Stage and atomically replace only the selected profile after validation. */
    private fun restoreProfileZip(archive: File, profile: File): Int {
        val stage = File(profile.parentFile, profile.name + ".restore_staging")
        val previous = File(profile.parentFile, profile.name + ".before_restore")
        check(!stage.exists() && !previous.exists()) { "Hay una restauración anterior pendiente." }
        check(stage.mkdirs()) { "No se pudo preparar la restauración." }
        var slots = 0
        try {
            ZipFile(archive).use { zip ->
                val entries = zip.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.isDirectory) continue
                    val target = File(stage, entry.name)
                    check(target.canonicalPath.startsWith(stage.canonicalPath + File.separator))
                    check(target.parentFile?.mkdirs() == true || target.parentFile?.isDirectory == true)
                    zip.getInputStream(entry).use { inp ->
                        target.outputStream().use { out -> inp.copyTo(out) }
                    }
                    if (entry.name.startsWith("partidas/") &&
                        entry.name.endsWith(".savc", ignoreCase = true) &&
                        !entry.name.contains("_bk", ignoreCase = true)) slots++
                }
            }
            check(profile.renameTo(previous)) { "No se pudo conservar la versión actual." }
            if (!stage.renameTo(profile)) {
                check(previous.renameTo(profile)) { "No se pudo recuperar la versión anterior." }
                error("No se pudo instalar el respaldo.")
            }
            previous.deleteRecursively()
            return slots
        } finally {
            stage.deleteRecursively()
        }
    }

    private fun verifyArchive(file: File) {
        ZipFile(file).use { zip ->
            var count = 0
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.isDirectory) continue
                val name = entry.name
                check(!name.contains("..") && !name.startsWith("/")) { "Archivo ZIP inseguro." }
                check(listOf("partidas/", "equipos/", "char_custom/").any { name.startsWith(it) }) {
                    "El respaldo contiene archivos ajenos al juego."
                }
                // Read the payload to validate its CRC rather than trusting the directory alone.
                val crc = CRC32()
                zip.getInputStream(entry).use { input ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        val size = input.read(buffer)
                        if (size == -1) break
                        crc.update(buffer, 0, size)
                    }
                }
                check(entry.crc == crc.value) { "Un archivo del respaldo está dañado." }
                count++
            }
            check(count > 0) { "El respaldo está vacío." }
        }
    }
}
