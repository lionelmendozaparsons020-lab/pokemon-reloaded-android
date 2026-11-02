package com.klisee.reloaded.ui

import android.os.Build
import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.klisee.reloaded.R
import androidx.core.view.WindowCompat

val LocalGlassTheme = staticCompositionLocalOf { true }

private val GlassColors = darkColorScheme(
    primary = Color(0xFFB6CCF8),
    onPrimary = Color(0xFF102445),
    primaryContainer = Color(0xFF2B303A),
    onPrimaryContainer = Color(0xFFF1F3F8),
    secondary = Color(0xFFC2C7D1),
    secondaryContainer = Color(0xFF33363D),
    onSecondaryContainer = Color(0xFFF1F2F5),
    background = Color(0xFF111214),
    onBackground = Color(0xFFF2F2F4),
    surface = Color(0xFF111214),
    onSurface = Color(0xFFF2F2F4),
    onSurfaceVariant = Color(0xFFB8BAC0),
    surfaceContainerLowest = Color(0xFF0D0E10),
    surfaceContainerLow = Color(0xFF18191B),
    surfaceContainer = Color(0xFF1B1C1F),
    surfaceContainerHigh = Color(0xFF202124),
    surfaceContainerHighest = Color(0xFF2B2D31),
    outline = Color(0xFF777A82),
    outlineVariant = Color(0xFF34363B),
    error = Color(0xFFF0ADB2),
    onError = Color(0xFF561C24),
)

/**
 * Google Sans Flex is the typeface Material 3 Expressive is designed around, and it is most of what
 * separates an expressive app from a plain Material one. It is a variable font, so the weight is
 * picked through a variation setting rather than separate files.
 */
private val SansFlex: FontFamily = FontFamily(
    Font(R.font.google_sans_flex, FontWeight.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(R.font.google_sans_flex, FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(560))),
    Font(R.font.google_sans_flex, FontWeight.SemiBold, variationSettings = FontVariation.Settings(FontVariation.weight(640))),
    Font(R.font.google_sans_flex, FontWeight.Bold, variationSettings = FontVariation.Settings(FontVariation.weight(760))),
)

/** The expressive corner scale: rounder than baseline Material, which is what gives the app its shape. */
private val ExpressiveShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(16.dp),
    medium = RoundedCornerShape(24.dp),
    large = RoundedCornerShape(32.dp),
    extraLarge = RoundedCornerShape(44.dp),
)

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ReloadedTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val preferences = remember(context) { context.getSharedPreferences("launcher", Context.MODE_PRIVATE) }
    var theme by remember(preferences) { mutableStateOf(preferences.getString("launcherTheme", "glass")) }
    DisposableEffect(preferences) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { store, key ->
            if (key == "launcherTheme") theme = store.getString(key, "glass")
        }
        preferences.registerOnSharedPreferenceChangeListener(listener)
        onDispose { preferences.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    val glass = theme != "material"
    val scheme = when {
        glass -> GlassColors
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> darkColorScheme()
        else -> expressiveLightColorScheme()
    }

    val typography = remember {
        val base = Typography()
        Typography(
            displayLarge = base.displayLarge.copy(fontFamily = SansFlex),
            displayMedium = base.displayMedium.copy(fontFamily = SansFlex),
            displaySmall = base.displaySmall.copy(fontFamily = SansFlex),
            headlineLarge = base.headlineLarge.copy(fontFamily = SansFlex),
            headlineMedium = base.headlineMedium.copy(fontFamily = SansFlex),
            headlineSmall = base.headlineSmall.copy(fontFamily = SansFlex),
            titleLarge = base.titleLarge.copy(fontFamily = SansFlex),
            titleMedium = base.titleMedium.copy(fontFamily = SansFlex),
            titleSmall = base.titleSmall.copy(fontFamily = SansFlex),
            bodyLarge = base.bodyLarge.copy(fontFamily = SansFlex),
            bodyMedium = base.bodyMedium.copy(fontFamily = SansFlex),
            bodySmall = base.bodySmall.copy(fontFamily = SansFlex),
            labelLarge = base.labelLarge.copy(fontFamily = SansFlex),
            labelMedium = base.labelMedium.copy(fontFamily = SansFlex),
            labelSmall = base.labelSmall.copy(fontFamily = SansFlex),
        )
    }

    val view = LocalView.current
    SideEffect {
        (context as? Activity)?.window?.let { window ->
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !glass && !dark
                isAppearanceLightNavigationBars = !glass && !dark
            }
        }
    }

    CompositionLocalProvider(LocalGlassTheme provides glass) {
      MaterialExpressiveTheme(
        colorScheme = scheme,
        motionScheme = MotionScheme.expressive(),
        typography = typography,
        shapes = ExpressiveShapes,
        content = content,
    )
    }
}
