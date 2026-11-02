package com.klisee.reloaded

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.espresso.Espresso.pressBack
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

/** Real launcher navigation and persisted engine settings; fixtures live only in the emulator. */
@RunWith(AndroidJUnit4::class)
class SettingsUiTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var sentinel: File

    @Before fun launch() {
        context.getSharedPreferences("launcher", Context.MODE_PRIVATE).edit().clear()
            .putBoolean("onboardingDone", true).putString("gameLanguage", "es")
            .putString("launcherTheme", "glass").commit()
        val game = File(context.filesDir, "game").apply { mkdirs() }
        File(game, "Reloaded 1.9.2.2.exe").writeText("UI fixture; never executed")
        repeat(5) { File(game, "data/folder$it").mkdirs() }
        sentinel = File(game, "partidas/ui-save-sentinel.bin").apply {
            parentFile!!.mkdirs(); writeBytes(byteArrayOf(1, 3, 5, 7, 9))
        }
        File(context.filesDir, "game.json").writeText(JSONObject()
            .put("version", "1.9.2.2").put("installedAt", 1793404800000L)
            .put("sizeBytes", 258L * 1024L * 1024L).toString())
        scenario = ActivityScenario.launch(MainActivity::class.java)
        openSettings()
    }

    @After fun close() { scenario.close() }

    private fun openSettings() {
        compose.onNodeWithContentDescription("Ajustes").performClick()
        compose.onNodeWithText("Cambiar tema").assertIsDisplayed()
    }

    private fun select(label: String) { compose.onNodeWithText(label).performScrollTo().performClick() }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val file = File(context.getExternalFilesDir(null), "screenshots/$name.png")
        file.parentFile!!.mkdirs()
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        checkNotNull(bitmap)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }

    @Test fun themeAppliesAndSurvivesRelaunch() {
        compose.onNodeWithText("1.9.2.2").assertIsDisplayed()
        compose.onNodeWithText("258 MB").assertIsDisplayed()
        screenshot("01-ajustes")
        select("Cambiar tema")
        compose.onNodeWithText("Material").performClick()
        compose.runOnIdle { assertEquals("material", Preferences(context).launcherTheme) }
        screenshot("02-tema-material")
        compose.onNodeWithText("Liquid Glass").performClick()
        screenshot("03-temas")
        pressBack()
        compose.onNodeWithText("Cerrar").performClick()
        compose.onNodeWithContentDescription("Ajustes").assertIsDisplayed()
        scenario.recreate()
        compose.runOnIdle { assertEquals("glass", Preferences(context).launcherTheme) }
        assertArrayEquals(byteArrayOf(1, 3, 5, 7, 9), sentinel.readBytes())
    }

    @Test fun videoSettingsPersistAndWriteTheEngineConfig() {
        select("FPS y pantalla")
        compose.onNodeWithText("30 FPS").assertIsSelected()
        compose.onNodeWithText("60 FPS").performClick()
        compose.runOnIdle { assertEquals("60", Preferences(context).renderMode) }
        if (Preferences(context).detectedRefreshRate() < 119.5f) {
            compose.onNodeWithText("120 FPS").assertIsNotEnabled()
            compose.onNodeWithText("Sin límite").assertIsNotEnabled()
        }
        screenshot("04-fps")
        select("Mantener la proporción")
        select("Mostrar FPS")
        compose.runOnIdle {
            val prefs = Preferences(context)
            assertTrue(prefs.keepAspect)
            assertTrue(prefs.showFps)
            val config = File(context.filesDir, "video.conf").readLines()
            assertTrue(config.contains("render=60"))
            assertTrue(config.contains("scaling=aspect"))
            assertTrue(config.contains("show_fps=1"))
        }
        screenshot("05-pantalla")
        pressBack()
        select("FPS y pantalla")
        compose.onNodeWithText("60 FPS").assertIsSelected()
        compose.onNodeWithText("Mantener la proporción").performScrollTo().assertIsSelected()
        assertArrayEquals(byteArrayOf(1, 3, 5, 7, 9), sentinel.readBytes())
    }

    @Test fun existingDestinationsAndCancelDeleteKeepWorking() {
        for ((row, destination) in listOf(
            "Gestionar mods" to "Mods y Cheats",
            "Mis partidas" to "Mis partidas · 6 slots",
            "Controles táctiles" to "Controles tactiles",
            "Mando" to "Controles",
        )) {
            select(row)
            compose.onNodeWithText(destination).assertIsDisplayed()
            pressBack()
            compose.onNodeWithText("Cambiar tema").assertExists()
        }
        select("Idioma")
        compose.onNodeWithText("Español").assertIsSelected()
        compose.onNodeWithText("Cerrar").performClick()
        select("Borrar el juego")
        compose.onNodeWithText("Cancelar").performClick()
        compose.runOnIdle { assertTrue(GameRepository(context).status() is GameRepository.Status.Ready) }
        assertArrayEquals(byteArrayOf(1, 3, 5, 7, 9), sentinel.readBytes())
    }
}
