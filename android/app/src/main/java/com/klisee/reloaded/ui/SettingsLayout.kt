package com.klisee.reloaded.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Shared layout keeps the settings inset from system gestures and readable on tablets/font zoom. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsPage(
    title: String,
    onBack: () -> Unit,
    close: Boolean = false,
    snackbar: SnackbarHostState? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    val background = if (LocalGlassTheme.current) {
        Brush.linearGradient(listOf(Color(0xFF242527), Color(0xFF0E0F11), Color(0xFF1E2023)))
    } else Brush.linearGradient(listOf(colors.background, colors.background))
    Box(Modifier.fillMaxSize().background(background)) {
        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text(title, style = MaterialTheme.typography.titleLarge) },
                    navigationIcon = {
                        if (close) TextButton(onClick = onBack) {
                            Text("Cerrar", color = colors.onSurface, style = MaterialTheme.typography.bodyLarge)
                        } else IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, Strings.tr("Volver"))
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                )
            },
            snackbarHost = { snackbar?.let { SnackbarHost(it) } },
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
                Column(
                    Modifier.widthIn(max = 640.dp).fillMaxWidth()
                        .testTag("settings-scroll")
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                    content = content,
                )
            }
        }
    }
}

@Composable
fun SettingsCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.97f),
    ) { Column(content = content) }
}

@Composable
fun SettingsSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            Strings.tr(title).uppercase(),
            Modifier.padding(start = 16.dp),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Normal,
            letterSpacing = 0.5.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SettingsCard(content = content)
    }
}

@Composable
fun SettingsDivider(inset: Boolean = true) {
    HorizontalDivider(
        Modifier.padding(start = if (inset) 56.dp else 16.dp, end = 0.dp),
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f),
    )
}

@Composable
fun SettingsAction(
    icon: ImageVector,
    title: String,
    subtitle: String,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    val tint = if (destructive) colors.error else colors.onSurface
    Row(
        Modifier.fillMaxWidth().clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (enabled) 1f else 0.45f)
            .heightIn(min = 76.dp).padding(horizontal = 16.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(icon, null, Modifier.size(22.dp), tint = tint)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, fontSize = 18.sp, lineHeight = 23.sp, fontWeight = FontWeight.Normal, color = tint)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(20.dp), tint = colors.onSurfaceVariant.copy(alpha = 0.65f))
    }
}
