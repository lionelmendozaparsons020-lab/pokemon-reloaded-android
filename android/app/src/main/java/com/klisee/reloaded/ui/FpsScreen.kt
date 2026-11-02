package com.klisee.reloaded.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.klisee.reloaded.Preferences

/** Video controls share one destination; all options write the engine's existing configuration. */
@Composable
fun FpsScreen(prefs: Preferences, onBack: () -> Unit) {
    val context = LocalContext.current
    var renderMode by remember { mutableStateOf(prefs.renderMode) }
    var showFps by remember { mutableStateOf(prefs.showFps) }
    var keepAspect by remember { mutableStateOf(prefs.keepAspect) }
    var keepScreenOn by remember { mutableStateOf(prefs.keepScreenOn) }
    val detectedHz = remember { prefs.detectedRefreshRate() }
    val supports60 = detectedHz >= 59.5f
    val supports120 = detectedHz >= 119.5f

    fun setFps(mode: String) {
        renderMode = mode
        prefs.renderMode = mode
        prefs.writeVideo(context.filesDir)
    }
    fun setAspect(keep: Boolean) {
        keepAspect = keep
        prefs.keepAspect = keep
        prefs.writeVideo(context.filesDir)
    }

    SettingsPage("FPS y pantalla", onBack) {
        SettingsGroup("Fotogramas por segundo") {
            ChoiceRow(Icons.Filled.Speed, "30 FPS", "Original · la velocidad clásica del juego.",
                selected = renderMode == "native", items = 4, index = 0, onSelect = { setFps("native") })
            ChoiceRow(Icons.Filled.Speed, "60 FPS", "Experimental · movimiento más fluido.",
                selected = renderMode == "60", items = 4, index = 1, enabled = supports60, onSelect = { setFps("60") })
            ChoiceRow(Icons.Filled.Speed, "120 FPS",
                if (supports120) "Experimental · para pantallas de 120 Hz." else "Requiere una pantalla compatible con 120 Hz.",
                selected = renderMode == "120", items = 4, index = 2, enabled = supports120, onSelect = { setFps("120") })
            ChoiceRow(Icons.Filled.Speed, "Sin límite",
                if (supports120) "Experimental · sin límite de renderizado." else "Requiere una pantalla compatible con 120 Hz.",
                selected = renderMode == "uncapped", items = 4, index = 3, enabled = supports120, onSelect = { setFps("uncapped") })
        }
        Text("Los modos experimentales interpolan la imagen. La lógica del juego conserva su velocidad original.",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SettingsGroup("Resolución") {
            ChoiceRow(Icons.Filled.Fullscreen, "Rellenar la pantalla", "Ocupa toda la pantalla, aunque la imagen se estire.",
                selected = !keepAspect, items = 2, index = 0, onSelect = { setAspect(false) })
            ChoiceRow(Icons.Filled.AspectRatio, "Mantener la proporción", "El aspecto del PC, con bandas a los lados.",
                selected = keepAspect, items = 2, index = 1, onSelect = { setAspect(true) })
        }
        SettingsGroup("Pantalla") {
            SwitchRow(Icons.Filled.Visibility, "Mostrar FPS", "Muestra el contador dentro del juego.",
                checked = showFps, items = 2, index = 0, onCheckedChange = {
                    showFps = it; prefs.showFps = it; prefs.writeVideo(context.filesDir)
                })
            SwitchRow(Icons.Filled.LightMode, "Mantener encendida", "Evita el bloqueo de pantalla mientras juegas.",
                checked = keepScreenOn, items = 2, index = 1, onCheckedChange = {
                    keepScreenOn = it; prefs.keepScreenOn = it
                })
        }
        Text("Los cambios de vídeo se aplican la próxima vez que abras el juego.",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
