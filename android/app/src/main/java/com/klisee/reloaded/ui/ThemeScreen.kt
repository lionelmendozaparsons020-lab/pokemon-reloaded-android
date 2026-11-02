package com.klisee.reloaded.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import com.klisee.reloaded.Preferences

@Composable
fun ThemeScreen(prefs: Preferences, onBack: () -> Unit) {
    var theme by remember { mutableStateOf(prefs.launcherTheme) }
    SettingsPage("Cambiar tema", onBack) {
        SettingsGroup("Apariencia") {
            ChoiceRow(
                Icons.Filled.DarkMode, "Liquid Glass", "Tarjetas oscuras, colores suaves y separadores sutiles.",
                selected = theme == "glass", items = 2, index = 0,
                onSelect = { theme = "glass"; prefs.launcherTheme = theme },
            )
            ChoiceRow(
                Icons.Filled.Palette, "Material", "Los colores del sistema y el estilo original de Android.",
                selected = theme == "material", items = 2, index = 1,
                onSelect = { theme = "material"; prefs.launcherTheme = theme },
            )
        }
        Text("El tema se aplica al instante y se conserva al volver a abrir la app.",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
