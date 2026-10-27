package com.klisee.reloaded.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.klisee.reloaded.GameRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * All six slots displayed simultaneously: three in Normal and three in Mods.
 * Every import/export/delete operation explicitly targets its own profile folder.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MySavesScreen(repo: GameRepository, onBack: () -> Unit) {
    val context = LocalContext.current
    val profileSaves = remember(context) { ProfileSaves(context) }
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var revision by remember { mutableStateOf(0) }
    var normalSlots by remember { mutableStateOf<List<GameRepository.SaveSlot>?>(null) }
    var modsSlots by remember { mutableStateOf<List<GameRepository.SaveSlot>?>(null) }
    var pendingExport by remember { mutableStateOf<Pair<SaveProfile, Int?>?>(null) }
    var pendingImport by remember { mutableStateOf<Pair<SaveProfile, Int?>?>(null) }
    var pendingDelete by remember { mutableStateOf<Pair<SaveProfile, Int>?>(null) }
    var busy by remember { mutableStateOf(false) }

    LaunchedEffect(revision) {
        val both = withContext(Dispatchers.IO) {
            profileSaves.slots(SaveProfile.NORMAL) to profileSaves.slots(SaveProfile.MODS)
        }
        normalSlots = both.first
        modsSlots = both.second
    }

    val exportPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/zip")
    ) { uri ->
        val selection = pendingExport
        pendingExport = null
        if (uri != null && selection != null) scope.launch {
            busy = true
            val file = profileSaves.export(selection.first, selection.second)
            val result = file.fold(
                onSuccess = { archive ->
                    try {
                        withContext(Dispatchers.IO) {
                            context.contentResolver.openOutputStream(uri)?.use { output ->
                                archive.inputStream().use { it.copyTo(output) }
                            } ?: error("No se pudo abrir el destino.")
                        }
                        "Archivo exportado de " + selection.first.label + "."
                    } catch (error: Exception) {
                        "No se pudo guardar: " + (error.message ?: "error")
                    } finally {
                        archive.delete()
                    }
                },
                onFailure = { error -> "No se pudo exportar: " + (error.message ?: "error") }
            )
            busy = false
            snackbar.showSnackbar(result)
        }
    }
    val importPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        val selection = pendingImport
        pendingImport = null
        if (uri != null && selection != null) scope.launch {
            busy = true
            val result = profileSaves.importArchive(selection.first, uri, selection.second)
            busy = false
            snackbar.showSnackbar(result.fold(
                onSuccess = { "Importado en " + selection.first.label + ": " + it + " archivos. Se creó un respaldo del perfil anterior." },
                onFailure = { "No se pudo importar: " + (it.message ?: "error") }
            ))
            revision++
        }
    }

    pendingDelete?.let { request ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            icon = { Icon(Icons.Filled.Warning, contentDescription = null) },
            title = { Text("Borrar partida · " + request.first.label) },
            text = {
                Text("Se borrará únicamente el slot " + request.second +
                    " del perfil " + request.first.label +
                    ". La partida del otro perfil NO se borrará. " +
                    "Exportá una copia antes de continuar.")
            },
            confirmButton = {
                TextButton(onClick = {
                    pendingDelete = null
                    scope.launch {
                        busy = true
                        val result = profileSaves.delete(request.first, request.second)
                        busy = false
                        snackbar.showSnackbar(result.fold(
                            { "Slot eliminado en " + request.first.label + "." },
                            { "No se pudo borrar: " + (it.message ?: "error") }
                        ))
                        revision++
                    }
                }) { Text("Sí, borrar este slot") }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("Cancelar") }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Mis partidas · 6 slots") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                    }
                }
            )
        },
        snackbarHost = {
            SnackbarHost(snackbar, modifier = Modifier.padding(bottom = BottomNavSpace))
        },
        contentWindowInsets = WindowInsets(0.dp)
    ) { padding ->
        Column(
            modifier = Modifier.padding(padding).fillMaxSize()
                .verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "Podés ver y administrar los dos perfiles sin cambiar de modo. " +
                "Son dos grupos independientes de tres partidas cada uno. " +
                "Para jugar, elegí el modo en «Mods y Cheats» y reiniciá el juego.",
                style = MaterialTheme.typography.bodySmall
            )
            val groups = listOf(
                SaveProfile.NORMAL to normalSlots,
                SaveProfile.MODS to modsSlots,
            )
            for ((profile, slots) in groups) {
                HorizontalDivider()
                Text(
                    if (profile == SaveProfile.NORMAL) "Partidas normales (3)"
                    else "Partidas con Mods (3)",
                    style = MaterialTheme.typography.titleLarge
                )
                if (!profileSaves.initialized(profile)) {
                    Text(
                        "Este perfil todavía no se inicializó. Abrí y cerrá el juego " +
                        "una vez en el modo " + profile.label + ".",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                if (slots == null) {
                    Text("Leyendo partidas...")
                } else {
                    for (slot in slots) {
                        SaveSlotCard(
                            slot = slot,
                            slotLabel = profile.label + " · Slot " + slot.index,
                            onExport = {
                                pendingExport = profile to slot.index
                                exportPicker.launch("reloaded_" + profile.folder +
                                    "_slot" + slot.index + ".zip")
                            },
                            onImport = {
                                pendingImport = profile to slot.index
                                importPicker.launch(arrayOf("application/zip", "application/octet-stream", "*/*"))
                            },
                            onDelete = { pendingDelete = profile to slot.index },
                            enabled = !busy && profileSaves.initialized(profile)
                        )
                    }
                }
                TextButton(
                    onClick = {
                        pendingExport = profile to null
                        exportPicker.launch("reloaded_" + profile.folder + "_todas.zip")
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !busy && profileSaves.initialized(profile),
                ) { Text("Exportar los 3 slots y equipos · " + profile.label) }
                TextButton(
                    onClick = {
                        pendingImport = profile to null
                        importPicker.launch(arrayOf("application/zip", "application/octet-stream", "*/*"))
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !busy && profileSaves.initialized(profile),
                ) { Text("Importar partidas y equipos · " + profile.label) }
            }
            Text(
                "Las importaciones guardan una copia de seguridad previa dentro de la app. " +
                "Cerrá siempre el juego antes de importar, exportar o borrar.",
                style = MaterialTheme.typography.bodySmall
            )
            Spacer(Modifier.height(BottomNavSpace))
        }
    }
}

/** One slot: what the game knows about it, and what can be done with it. */
@Composable
private fun SaveSlotCard(
    slot: GameRepository.SaveSlot,
    slotLabel: String,
    enabled: Boolean,
    onExport: () -> Unit,
    onImport: () -> Unit,
    onDelete: () -> Unit,
) {
    val filled = slot.name != null
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(
            containerColor = if (filled) {
                MaterialTheme.colorScheme.surfaceContainerHigh
            } else {
                MaterialTheme.colorScheme.surfaceContainerLow
            },
        ),
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Filled.Save,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.size(12.dp))
                Text(
                    text = slotLabel,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(Modifier.weight(1f))
                // Only a slot with something in it can be deleted.
                if (filled) {
                    IconButton(onClick = onDelete, enabled = enabled) {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = "Borrar la partida",
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }

            Spacer(Modifier.height(12.dp))

            if (!filled) {
                Text(
                    text = "Ranura vacia",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text(slot.name.orEmpty(), style = MaterialTheme.typography.headlineSmall)
                Spacer(Modifier.height(8.dp))
                Text("Vistos: ${slot.seen ?: "?"}", style = MaterialTheme.typography.bodyLarge)
                Text("Capturados: ${slot.caught ?: "?"}", style = MaterialTheme.typography.bodyLarge)
                Text("Localizacion: ${slot.place ?: "?"}", style = MaterialTheme.typography.bodyLarge)
            }

            Spacer(Modifier.height(8.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onExport, enabled = enabled && filled) {
                    Icon(Icons.Filled.FileDownload, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.size(8.dp))
                    Text("Exportar partida")
                }
                TextButton(onClick = onImport, enabled = enabled) {
                    Icon(Icons.Filled.FileUpload, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.size(8.dp))
                    Text("Importar partida")
                }
            }
        }
    }
}
