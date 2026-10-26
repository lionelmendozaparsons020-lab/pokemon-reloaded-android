package com.klisee.reloaded.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.klisee.reloaded.GameRepository
import com.klisee.reloaded.ModSupport
import kotlinx.coroutines.launch
import java.io.File
import java.text.DateFormat
import java.util.Date

/**
 * In-game commands for the verified GameMaker 8 executable 1.9.2.2.
 * Backups and the stock F3 entry point remain intact. Extra commands call
 * native game routines, NOT an off-game save editor or anti-cheat bypass.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModsCheatsScreen(repo: GameRepository, onBack: () -> Unit) {
    val context = LocalContext.current
    val mods = remember(context) { ModSupport(context) }
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var officialF3 by remember { mutableStateOf(mods.showOfficialF3) }
    var backups by remember { mutableStateOf(mods.backups()) }
    var busy by remember { mutableStateOf(false) }
    var restoring by remember { mutableStateOf<File?>(null) }

    restoring?.let { backup ->
        AlertDialog(
            onDismissRequest = { restoring = null },
            title = { Text("Restaurar partida") },
            text = { Text("Se hará un nuevo respaldo de las partidas actuales antes de sobrescribir los archivos del respaldo elegido. Hacelo con el juego cerrado.") },
            confirmButton = {
                TextButton(onClick = {
                    restoring = null
                    busy = true
                    scope.launch {
                        val result = mods.restoreBackup(repo, backup)
                        busy = false
                        backups = mods.backups()
                        snackbar.showSnackbar(result.fold(
                            { "Respaldo restaurado. Reiniciá el juego para cargarlo." },
                            { "No se pudo restaurar: " + (it.message ?: "error") },
                        ))
                    }
                }) { Text("Restaurar") }
            },
            dismissButton = { TextButton(onClick = { restoring = null }) { Text("Cancelar") } },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Mods y Cheats") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = WindowInsets(0.dp),
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Trucos oficiales", style = MaterialTheme.typography.titleLarge)
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Botón F3 en pantalla")
                    Text(
                        "Muestra F3 al explorar el mundo. Abre el cuadro de códigos que ya trae Pokémon Reloaded.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = officialF3,
                    onCheckedChange = { checked ->
                        runCatching { mods.showOfficialF3 = checked }
                            .onSuccess { officialF3 = checked }
                            .onFailure { error ->
                                scope.launch { snackbar.showSnackbar("No se pudo guardar: " + error.message) }
                            }
                    },
                )
            }
            Text(
                "Reiniciá el juego para aplicar el cambio. Los trucos oficiales son diferentes de modificar archivos externos.",
                style = MaterialTheme.typography.bodySmall,
            )

            Text("Protección de partidas", style = MaterialTheme.typography.titleLarge)
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        val result = mods.createBackup(repo)
                        busy = false
                        backups = mods.backups()
                        snackbar.showSnackbar(result.fold(
                            { "Respaldo guardado: " + it.name },
                            { "No se pudo respaldar: " + (it.message ?: "error") },
                        ))
                    }
                },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (busy) "Procesando…" else "Crear copia de seguridad")
            }
            if (backups.isEmpty()) {
                Text("Todavía no hay respaldos.", style = MaterialTheme.typography.bodySmall)
            } else {
                Text("Respaldos guardados en la app", style = MaterialTheme.typography.titleMedium)
                backups.forEach { file ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(file.name, style = MaterialTheme.typography.bodySmall)
                            Text(
                                DateFormat.getDateTimeInstance().format(Date(file.lastModified())),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        }
                        OutlinedButton(
                            onClick = { restoring = file },
                            enabled = !busy,
                        ) { Text("Restaurar") }
                    }
                }
            }

            Text("Aviso de seguridad", style = MaterialTheme.typography.titleLarge)
            Text(
                "Los comandos experimentales RAD100K y RADITEM están desactivados. " +
                    "El juego detectó una anomalía 10551 al utilizarlos y terminó la sesión. " +
                    "No guardes una partida después de recibir ese aviso.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                "El botón F3 sigue disponible para los trucos oficiales del juego. " +
                    "Primero creá un respaldo. Esta versión no altera el formato de las partidas " +
                    "ni desactiva las comprobaciones del juego.",
                style = MaterialTheme.typography.bodySmall,
            )
            Spacer(Modifier.padding(bottom = BottomNavSpace))
        }
    }
}
