package com.klisee.reloaded.ui

import android.content.Context
import android.net.Uri
import com.klisee.reloaded.GameRepository
import com.klisee.reloaded.GameSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

enum class SaveProfile(val folder: String, val label: String) {
    NORMAL("normal", "Normal"), MODS("mods", "Mods")
}

/** Each save profile is accessed DIRECTLY: never through game/data, which switches profile. */
class ProfileSaves(private val context: Context) {
    private val folders = listOf("partidas", "equipos", "char_custom")
    private fun path(profile: SaveProfile): File =
        File(context.filesDir, "save_modes/" + profile.folder)
    private fun root(profile: SaveProfile): File = path(profile).also {
        check(it.isDirectory) { "Abrí y cerrá el juego una vez para preparar las partidas de " + profile.label }
        check(!java.nio.file.Files.isSymbolicLink(it.toPath())) { "Perfil de guardado inválido." }
    }
    fun initialized(profile: SaveProfile): Boolean = path(profile).isDirectory
    private fun checkClosed() { check(!GameSession.active) { "Cerrá el juego antes de modificar los guardados." } }
    private fun belongsToSlot(name: String, slot: Int): Boolean =
        (name.startsWith("reloaded$slot.") || name.startsWith("reloaded${slot}_")) &&
            Regex("[A-Za-z0-9._-]{1,100}").matches(name)

    fun slots(profile: SaveProfile): List<GameRepository.SaveSlot> {
        val folder = File(path(profile), "partidas")
        return (1..3).map { slot ->
            val found = folder.listFiles().orEmpty().any { it.isFile && belongsToSlot(it.name, slot) }
            if (!found) GameRepository.SaveSlot(slot, null, null, null, null)
            else {
                val nfo = runCatching { File(folder, "reloaded$slot.nfo").readLines() }
                    .getOrDefault(emptyList()).map { it.trim() }.filter { it.isNotBlank() }
                GameRepository.SaveSlot(slot, nfo.getOrNull(0), nfo.getOrNull(1),
                    nfo.getOrNull(2), nfo.getOrNull(3))
            }
        }
    }

    suspend fun export(profile: SaveProfile, slot: Int?): Result<File> = withContext(Dispatchers.IO) {
        runCatching {
            checkClosed()
            if (slot != null) require(slot in 1..3)
            val source = root(profile)
            val out = File.createTempFile("reloaded_${profile.folder}_", ".zip", context.cacheDir)
            try {
                var count = 0
                ZipOutputStream(out.outputStream().buffered()).use { zip ->
                    for (folderName in folders) {
                        if (slot != null && folderName != "partidas") continue
                        val folder = File(source, folderName)
                        if (!folder.isDirectory) continue
                        for (file in folder.walkTopDown().filter { it.isFile }) {
                            if (slot != null && !belongsToSlot(file.name, slot)) continue
                            check(!java.nio.file.Files.isSymbolicLink(file.toPath())) { "Enlace inesperado." }
                            zip.putNextEntry(ZipEntry("$folderName/" + file.relativeTo(folder).invariantSeparatorsPath))
                            file.inputStream().use { it.copyTo(zip) }
                            zip.closeEntry()
                            count++
                        }
                    }
                }
                check(count > 0) { "No hay archivos para exportar en " + profile.label }
                out
            } catch (ex: Exception) { out.delete(); throw ex }
        }
    }

    suspend fun delete(profile: SaveProfile, slot: Int): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            checkClosed()
            require(slot in 1..3)
            val files = File(root(profile), "partidas").listFiles().orEmpty()
                .filter { it.isFile && belongsToSlot(it.name, slot) }
            check(files.isNotEmpty()) { "Ranura vacía." }
            files.forEach { check(it.delete()) { "No se pudo borrar: " + it.name } }
        }
    }

    private data class Staged(val dest: File, val temp: File)

    suspend fun importArchive(profile: SaveProfile, uri: Uri, targetSlot: Int?): Result<Int> =
        withContext(Dispatchers.IO) {
            runCatching {
                checkClosed()
                if (targetSlot != null) require(targetSlot in 1..3)
                val sourceRoot = root(profile).canonicalFile
                val staged = mutableListOf<Staged>()
                val used = mutableSetOf<String>()
                var bytes = 0L
                try {
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        ZipInputStream(input.buffered()).use { zip ->
                            var entry = zip.nextEntry
                            var count = 0
                            while (entry != null) {
                                count++
                                check(count <= 2048) { "Demasiados archivos en el ZIP." }
                                val sections = entry.name.split('/')
                                val category = sections.firstOrNull()
                                val safe = !entry.isDirectory && sections.size >= 2 &&
                                    category in folders && sections.drop(1).all {
                                        it != "." && it != ".." && Regex("[A-Za-z0-9._ -]{1,100}").matches(it)
                                    }
                                if (safe) {
                                    val original = sections.last()
                                    val renamed = if (targetSlot != null) {
                                        val suffix = Regex("^reloaded[1-3]([._].+)$", RegexOption.IGNORE_CASE)
                                            .matchEntire(original)?.groupValues?.get(1)
                                        if (category == "partidas" && sections.size == 2 && suffix != null)
                                            "reloaded$targetSlot$suffix" else null
                                    } else original
                                    if (renamed != null) {
                                        val rel = if (targetSlot == null) entry.name
                                            else "partidas/" + renamed
                                        check(used.add(rel)) { "Archivo duplicado en el ZIP." }
                                        val dest = File(sourceRoot, rel)
                                        check(dest.canonicalPath.startsWith(sourceRoot.path + File.separator)) {
                                            "Ruta no permitida."
                                        }
                                        val tmp = File.createTempFile("reload-stage-", ".tmp", context.cacheDir)
                                        staged.add(Staged(dest, tmp))
                                        tmp.outputStream().buffered().use { out ->
                                            val buffer = ByteArray(65536)
                                            var fileBytes = 0L
                                            while (true) {
                                                val n = zip.read(buffer)
                                                if (n < 0) break
                                                fileBytes += n
                                                bytes += n
                                                check(fileBytes <= 64L * 1024 * 1024 &&
                                                    bytes <= 256L * 1024 * 1024) { "ZIP demasiado grande." }
                                                out.write(buffer, 0, n)
                                            }
                                        }
                                    }
                                }
                                zip.closeEntry()
                                entry = zip.nextEntry
                            }
                        }
                    } ?: error("No pude abrir el archivo seleccionado.")
                    check(staged.isNotEmpty()) { "El ZIP no contiene archivos de partida reconocidos." }

                    // Preserve the selected profile BEFORE writing any replacement files.
                    val backupFolder = File(context.filesDir, "save_modes_import_backups")
                    check(backupFolder.isDirectory || backupFolder.mkdirs())
                    val backup = File(backupFolder, profile.folder + "_" + System.currentTimeMillis() + ".zip")
                    var previous = 0
                    ZipOutputStream(backup.outputStream().buffered()).use { zip ->
                        folders.forEach { folderName ->
                            val dir = File(sourceRoot, folderName)
                            if (dir.isDirectory) for (file in dir.walkTopDown().filter { it.isFile }) {
                                check(!java.nio.file.Files.isSymbolicLink(file.toPath()))
                                zip.putNextEntry(ZipEntry("$folderName/" + file.relativeTo(dir).invariantSeparatorsPath))
                                file.inputStream().use { it.copyTo(zip) }
                                zip.closeEntry()
                                previous++
                            }
                        }
                    }
                    if (previous == 0) backup.delete()
                    staged.forEach { stagedFile ->
                        val dest = stagedFile.dest
                        val parent = dest.parentFile!!
                        check(parent.isDirectory || parent.mkdirs())
                        check(!java.nio.file.Files.isSymbolicLink(dest.toPath()))
                        val newFile = File.createTempFile(".reload-import-", ".tmp", parent)
                        try {
                            stagedFile.temp.inputStream().use { it.copyTo(newFile.outputStream()) }
                            check(newFile.renameTo(dest)) { "No se pudo reemplazar " + dest.name }
                        } finally { newFile.delete() }
                    }
                    staged.size
                } finally {
                    staged.forEach { it.temp.delete() }
                }
            }
        }
}
