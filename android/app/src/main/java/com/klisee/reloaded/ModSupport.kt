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

    var showOfficialF3: Boolean
        get() = settings.getBoolean("officialF3", false)
        set(value) {
            check(settings.edit().putBoolean("officialF3", value).commit()) {
                "No se pudo guardar la preferencia."
            }
            writeRuntimeConfig()
        }

    /** Loaded by the native touch overlay when starting the game. */
    fun writeRuntimeConfig() {
        val atomic = AtomicFile(File(context.filesDir, "mods.conf"))
        val stream = atomic.startWrite()
        try {
            stream.write(if (showOfficialF3) "official_f3=1\n".toByteArray() else "official_f3=0\n".toByteArray())
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
    }

    fun backups(): List<File> =
        backupsDir.listFiles()
            ?.filter { it.isFile && it.name.startsWith("respaldo_") && it.extension == "zip" }
            ?.sortedByDescending { it.name }
            .orEmpty()

    /**
     * Take a REAL immutable snapshot of partidas/equipos/char_custom, not a reference to
     * the mutable cache file used by the existing export screen. The temp file is verified
     * before the final rename, so incomplete exports are never presented as backups.
     */
    suspend fun createBackup(repo: GameRepository): Result<File> = withContext(Dispatchers.IO) {
        runCatching {
            check(repo.status() is GameRepository.Status.Ready) { "Instalá el juego primero." }
            val source = repo.exportSaves().getOrThrow()
            check(backupsDir.isDirectory || backupsDir.mkdirs()) {
                "No se pudo crear la carpeta de respaldos."
            }
            val name = "respaldo_" +
                SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date()) + ".zip"
            val finished = File(backupsDir, name)
            val partial = File(backupsDir, name + ".partial")
            try {
                source.copyTo(partial, overwrite = false)
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
            check(backup.parentFile?.canonicalFile == backupsDir.canonicalFile &&
                backup in backups() && backup.isFile) { "Respaldo no válido." }
            verifyArchive(backup)
            val data = File(context.filesDir, "game/data")
            val currentFiles = listOf("partidas", "equipos", "char_custom").any { folder ->
                File(data, folder).walkTopDown().any { it.isFile }
            }
            if (currentFiles) createBackup(repo).getOrThrow()
            repo.importSaves(Uri.fromFile(backup)).getOrThrow()
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
