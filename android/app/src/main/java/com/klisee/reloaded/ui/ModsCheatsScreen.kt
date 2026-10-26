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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.FilterChip
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
    var isolatedMode by remember { mutableStateOf(mods.modMode) }
    var backups by remember { mutableStateOf(mods.backups()) }
    var pokemonId by remember { mutableStateOf("25") }
    var pokemonLevel by remember { mutableStateOf("10") }
    var pokemonShiny by remember { mutableStateOf(false) }
    var teamSlot by remember { mutableStateOf("1") }
    var selectedStat by remember { mutableStateOf(1) }
    var busy by remember { mutableStateOf(false) }
    var restoring by remember { mutableStateOf<File?>(null) }
    fun copyCheat(code: String, message: String) {
        val clipboard = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE)
            as android.content.ClipboardManager
        clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Pokémon Reloaded F3",code))
        scope.launch { snackbar.showSnackbar(message) }
    }

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

            Text("Modo Mods experimental", style = MaterialTheme.typography.titleLarge)
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Usar partida independiente")
                    Text(
                        "El modo normal no comparte guardados con Modo Mods. El primer inicio " +
                            "crea una copia de tu progreso actual y después avanzan por separado.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = isolatedMode,
                    onCheckedChange = { enabled ->
                        runCatching { mods.modMode = enabled }
                            .onSuccess { isolatedMode = enabled }
                            .onFailure { error ->
                                scope.launch { snackbar.showSnackbar(error.message ?: "No se pudo cambiar de modo") }
                            }
                    },
                )
            }
            if (isolatedMode) {
                Text(
                    "MODO MODS ACTIVADO · Reiniciá el juego. Prueba únicamente con una copia " +
                        "de partida. El modo experimental no garantiza que el juego acepte todos los objetos.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text("RAD100K — entrega hasta 100.000 de dinero.")
                Text("RADITEM — entrega 10 unidades del objeto ID 1.")
                Text("RADITEM1X12 — entrega 12 unidades del objeto ID 1.")
                Text("RADITEM4X10 — prueba 10 Master Balls en la partida experimental.")
                Text(
                    "Corrección experimental: al cargar, Modo Mods admite Master Balls " +
                        "adicionales sin alterar los verificadores generales del guardado. " +
                        "Probalo solo con respaldo y no guardes ante otra anomalía.",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    "RADITEM + ID + X + cantidad (máximo 99); solo objetos comunes y Poké Balls. " +
                        "Estos comandos están disponibles únicamente dentro de Modo Mods.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Text("Guía rápida · usar Mods y Cheats", style = MaterialTheme.typography.titleLarge)
            Text(
                "1. Cerrá el juego y tocá «Crear copia de seguridad» abajo. " +
                "2. Activá «Usar partida independiente» y «Botón F3 en pantalla». " +
                "3. Iniciá o reiniciá Pokémon Reloaded. " +
                "4. Durante la exploración tocá F3, escribí el código que copiaste aquí " +
                "y confirmá con Enter/OK. Algunos códigos no funcionan en combate, menús o diálogos. " +
                "5. Probá el resultado. Guardá, cerrá y volvé a cargar el modo experimental para comprobarlo.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                "Si copiás un código, tenés que introducirlo en el cuadro de F3 dentro del juego: " +
                "el botón de copiar no ejecuta el truco por sí solo. Si aparece «Corrupción» " +
                "o «Anomalía», NO guardes; salí y restaurá el respaldo.",
                style = MaterialTheme.typography.bodySmall,
            )
            Text("Pokémon de eventos anticipados", style = MaterialTheme.typography.titleLarge)
            Text(
                "En Modo Mods se admiten capturas adelantadas de las especies del catálogo de eventos, " +
                    "incluido Cosmog, aunque todavía no hayas completado su misión. Esto no completa " +
                    "medallas, misiones ni eventos por vos y no afecta el Modo Normal. " +
                    "Se mantienen las comprobaciones de integridad del guardado y del inventario.",
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                "Si antes tenías «Corrupción J100E980» u otro J…E… por una captura anticipada, " +
                    "probá cargar el mismo slot desde Modo Mods. Hacé un respaldo primero. " +
                    "No guardes si aparece una anomalía diferente.",
                style = MaterialTheme.typography.bodySmall,
            )
            Text("Añadir Pokémon · Encuentro", style = MaterialTheme.typography.titleLarge)
            Text(
                "Elegí especie y nivel. Modo Mods prepara un encuentro salvaje para capturarlo " +
                    "con las funciones originales del juego, sin editar directamente tu equipo o tus cajas.",
                style = MaterialTheme.typography.bodySmall,
            )
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = pokemonId,
                    onValueChange = { pokemonId = it.filter { ch -> ch.isDigit() }.take(4) },
                    label = { Text("ID Pokémon") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = pokemonLevel,
                    onValueChange = { pokemonLevel = it.filter { ch -> ch.isDigit() }.take(3) },
                    label = { Text("Nivel") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }
            Text("Ejemplos: Bulbasaur 1 · Charizard 6 · Pikachu 25 · Eevee 133 · Mewtwo 150 · Lucario 448.",
                style = MaterialTheme.typography.bodySmall)
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Pokémon shiny (variocolor)")
                    Text("El próximo encuentro creado por este código será shiny; luego hay que capturarlo.",
                        style = MaterialTheme.typography.bodySmall)
                }
                Switch(checked = pokemonShiny, onCheckedChange = { pokemonShiny = it })
            }
            val pokemonCode = (if (pokemonShiny) "RADSH" else "RADPK") + pokemonId + "X" + pokemonLevel
            Button(
                enabled = isolatedMode && (pokemonId.toIntOrNull() ?: 0) in 1..1025 &&
                    (pokemonLevel.toIntOrNull() ?: 0) in 1..100 && pokemonCode.length <= 13,
                onClick = {
                    copyCheat(pokemonCode, "Copiado: $pokemonCode. Escribilo en F3 al explorar.")
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Copiar código: $pokemonCode") }
            Text(
                "Requiere Modo Mods y F3 activados. Al explorar, introducí el código en F3 " +
                    "para iniciar un encuentro y capturarlo de forma normal. " +
                    "Solo funciona con especies válidas. No guardes si aparece una anomalía.",
                style = MaterialTheme.typography.bodySmall,
            )


            Text("Cambiar talento natural (NTV) de tu equipo", style = MaterialTheme.typography.titleLarge)
            Text(
                "Los NTV son los valores naturales de cada Pokémon; no son los IV de entrenamiento. " +
                "En Reloaded los seis NTV van de 1 a 10. Aquí los subimos con la función original " +
                "del juego, que también actualiza las comprobaciones internas. " +
                "No modifica directamente el archivo .savc.",
                style = MaterialTheme.typography.bodySmall,
            )
            OutlinedTextField(
                value = teamSlot,
                onValueChange = { teamSlot = it.filter(Char::isDigit).take(1) },
                label = { Text("Posición del Pokémon en tu equipo (1 a 6)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Text("Elegí qué talento natural mejorar:", style = MaterialTheme.typography.titleMedium)
            val naturalStats = listOf("PS", "Ataque", "Defensa", "At. Esp.", "Def. Esp.", "Velocidad")
            naturalStats.chunked(3).forEachIndexed { rowIndex, group ->
                Row(modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    group.forEachIndexed { colIndex, label ->
                        val statIndex = rowIndex * 3 + colIndex + 1
                        FilterChip(
                            selected = selectedStat == statIndex,
                            onClick = { selectedStat = statIndex },
                            label = { Text(label) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
            val slotOk = (teamSlot.toIntOrNull() ?: 0) in 1..6
            val statCode = "RADNV" + teamSlot + "X" + selectedStat
            val maxCode = "RADMX" + teamSlot
            Button(
                onClick = { copyCheat(statCode, "Código $statCode copiado. Subirá un punto el NTV seleccionado.") },
                enabled = isolatedMode && slotOk,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Subir un nivel natural: $statCode") }
            OutlinedButton(
                onClick = { copyCheat(maxCode, "Código $maxCode copiado. NTV completos al máximo (10).") },
                enabled = isolatedMode && slotOk,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("NTV al máximo del Pokémon: $maxCode") }
            Text(
                "Ejemplo: RADNV1X6 aumenta un punto la Velocidad natural del primer Pokémon. " +
                "RADMX1 establece al máximo los seis NTV del primer Pokémon. " +
                "Si ya está al máximo, no hace nada. La posición es la del equipo, NO de la caja.",
                style = MaterialTheme.typography.bodySmall,
            )

            Text("Shiny de un Pokémon que ya tenés", style = MaterialTheme.typography.titleLarge)
            Text(
                "La opción shiny del encuentro afecta al Pokémon salvaje nuevo, no transforma a " +
                "uno de tu equipo. Para convertir uno existente, Reloaded trae la Máquina Shinyficadora: " +
                "al cumplir los requisitos de la historia, escribí SHINY en F3 para consultar " +
                "la contraseña de esa partida, y usala en la máquina.",
                style = MaterialTheme.typography.bodySmall,
            )
            OutlinedButton(onClick = {
                copyCheat("SHINY", "SHINY copiado. Funciona al cumplir los requisitos del juego.")
            }, modifier = Modifier.fillMaxWidth()) { Text("Copiar código oficial SHINY") }

            Text("IV de entrenamiento · objetos", style = MaterialTheme.typography.titleLarge)
            Text(
                "Los IV de entrenamiento (0–9) son distintos de los NTV. " +
                "En Reloaded mejoran al entrenar o usar vitaminas. Podés probar " +
                "RADITEM36X5 para obtener 5 Proteínas (Ataque), " +
                "RADITEM33X5 para Calcio (At. Esp.) o RADITEM37X5 para Zinc (Def. Esp.). " +
                "Después utilizá esos objetos normalmente en la mochila. No confundas IV con NTV.",
                style = MaterialTheme.typography.bodySmall,
            )

            Text("Los cambios de modo se aplican al volver a iniciar el juego.", style = MaterialTheme.typography.bodySmall)

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

            Text("Protección y diagnóstico", style = MaterialTheme.typography.titleLarge)
            Text(
                "La versión anterior producía la anomalía 10551 al ejecutar acciones " +
                    "de objetos desde F3. Esta versión usa el contexto de jugador original " +
                    "y no desactiva la validación de inventario o dinero. " +
                    "No guardes si aparece cualquier aviso de anomalía.",
                style = MaterialTheme.typography.bodySmall,
            )
            Spacer(Modifier.padding(bottom = BottomNavSpace))
        }
    }
}
