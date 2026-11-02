package com.klisee.reloaded.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.klisee.reloaded.GameRepository
import com.klisee.reloaded.Preferences
import com.klisee.reloaded.R
import com.klisee.reloaded.Update
import com.klisee.reloaded.discord.DiscordRpcManager
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    repo: GameRepository,
    prefs: Preferences,
    revision: Int = 0,
    onClose: () -> Unit,
    onTheme: () -> Unit,
    onLog: () -> Unit,
    onAbout: () -> Unit,
    onControls: () -> Unit,
    onDiscord: () -> Unit,
    onTouchSettings: () -> Unit,
    onFpsSettings: () -> Unit,
    onMySaves: () -> Unit,
    onMods: () -> Unit,
    onUpdateFound: (Update.Release) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var status by remember(revision) { mutableStateOf(repo.status()) }
    var gameLanguage by remember { mutableStateOf(prefs.gameLanguage) }
    var showLanguage by remember { mutableStateOf(false) }
    val discordUser by DiscordRpcManager.user.collectAsState()
    var checking by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    val appVersion = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty()
    }
    val installed = status as? GameRepository.Status.Ready

    if (showLanguage) AlertDialog(
        onDismissRequest = { showLanguage = false },
        title = { Text("Idioma") },
        text = {
            Column {
                listOf("auto" to "Automático", "es" to "Español", "en" to "English").forEachIndexed { i, (mode, title) ->
                    ChoiceRow(
                        Icons.Filled.Language, title,
                        if (mode == "auto") "Según el idioma del teléfono" else title,
                        selected = gameLanguage == mode, items = 3, index = i,
                        onSelect = {
                            gameLanguage = mode
                            prefs.gameLanguage = mode
                            Strings.update(prefs)
                            if (installed != null) prefs.writeGameLanguage(context.filesDir)
                            DiscordRpcManager.setLauncherScreen(
                                if (DiscordRpcManager.isEnglish()) "In Settings" else "En los Ajustes",
                            )
                            showLanguage = false
                        },
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = { showLanguage = false }) { Text("Cerrar") } },
    )

    if (confirmingDelete) AlertDialog(
        onDismissRequest = { confirmingDelete = false },
        title = { Text("¿Borrar el juego?") },
        text = { Text("Se eliminarán los archivos del juego y las partidas que estén dentro. Exporta tus partidas antes de continuar.") },
        confirmButton = {
            TextButton(onClick = {
                confirmingDelete = false
                deleting = true
                scope.launch {
                    repo.deleteGame()
                    status = repo.status()
                    deleting = false
                }
            }) { Text("Borrar", color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton(onClick = { confirmingDelete = false }) { Text("Cancelar") } },
    )

    SettingsPage("Ajustes", onClose, close = true, snackbar = snackbar) {
        SettingsCard {
            Row(
                Modifier.fillMaxWidth().padding(16.dp, 20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Box(
                    Modifier.size(56.dp).background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.CatchingPokemon, null, Modifier.size(30.dp)) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Reloaded OpenGMK", fontSize = 20.sp, lineHeight = 25.sp)
                    Text("OpenGMK · v$appVersion", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            SettingsDivider(inset = false)
            SettingsAction(Icons.Filled.Palette, "Cambiar tema",
                if (LocalGlassTheme.current) "Liquid Glass" else "Material", onClick = onTheme)
        }

        SettingsSection("Juego") {
            if (installed != null) {
                Row(Modifier.fillMaxWidth().padding(16.dp, 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    GameDetail("Versión", installed.version ?: "—", Modifier.weight(1f))
                    GameDetail("Tamaño", formatBytes(installed.sizeBytes), Modifier.weight(1f))
                    GameDetail("Instalado", formatDate(installed.installedAt), Modifier.weight(1.15f))
                }
            } else {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text("Sin juego instalado", style = MaterialTheme.typography.titleMedium)
                    Text("Descarga o importa el ZIP desde Inicio.", style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            SettingsDivider(inset = false)
            SettingsAction(Icons.Filled.Build, "Gestionar mods", "Activa o desactiva los mods del juego",
                enabled = installed != null && !deleting, onClick = onMods)
            SettingsDivider()
            SettingsAction(Icons.Filled.Save, "Mis partidas", "Consulta, importa y exporta tus partidas",
                enabled = installed != null && !deleting, onClick = onMySaves)
            SettingsDivider()
            SettingsAction(Icons.Filled.Delete, "Borrar el juego",
                if (deleting) "Borrando…" else installed?.let { "${Strings.tr("Libera")} ${formatBytes(it.sizeBytes)}" } ?: "Sin archivos del juego",
                enabled = installed != null && !deleting, destructive = true, onClick = { confirmingDelete = true })
        }

        SettingsSection("General") {
            SettingsAction(Icons.Filled.Language, "Idioma", when (gameLanguage) {
                "es" -> "Español"; "en" -> "English"; else -> "Automático"
            }, onClick = { showLanguage = true })
            SettingsDivider()
            SettingsAction(Icons.Filled.VideogameAsset, "Controles táctiles", "Estilo, movimiento y editores", onClick = onTouchSettings)
            SettingsDivider()
            SettingsAction(Icons.Filled.SportsEsports, "Mando", "Botones y prueba del mando", onClick = onControls)
            SettingsDivider()
            SettingsAction(Icons.Filled.Speed, "FPS y pantalla", "Framerate, aspecto y contador", onClick = onFpsSettings)
        }

        SettingsSection("Conexiones") {
            SettingsAction(ImageVector.vectorResource(R.drawable.ic_discord), "Discord",
                discordUser ?: if (prefs.discordEnabled) "Rich Presence activado" else "Muestra lo que estás jugando", onClick = onDiscord)
        }

        SettingsSection("Información y ayuda") {
            SettingsAction(Icons.Filled.SystemUpdate, "Buscar actualizaciones",
                if (checking) "Buscando…" else "${Strings.tr("Versión")} $appVersion", enabled = !checking,
                onClick = {
                    checking = true
                    scope.launch {
                        val result = Update.check(appVersion)
                        checking = false
                        result.fold(
                            onSuccess = { found ->
                                if (found != null) onUpdateFound(found)
                                else snackbar.showSnackbar(Strings.tr("No hay actualizaciones disponibles."))
                            },
                            onFailure = { snackbar.showSnackbar(Strings.tr("No se pudo comprobar la actualización. Inténtalo de nuevo.")) },
                        )
                    }
                })
            SettingsDivider()
            SettingsAction(Icons.Filled.Article, "Logs", "Consulta y comparte el registro de errores", onClick = onLog)
            SettingsDivider()
            SettingsAction(Icons.Filled.Info, "Acerca de", "Versión, créditos y avisos", onClick = onAbout)
        }
    }
}

@Composable
private fun GameDetail(label: String, value: String, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}
