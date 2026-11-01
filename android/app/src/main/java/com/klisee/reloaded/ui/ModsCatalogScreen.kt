package com.klisee.reloaded.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import java.text.Normalizer
import java.io.File

private fun searchable(text: String): String =
    Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD)
        .replace(Regex("[\\u0300-\\u036f]"), "")
        .replace(Regex("[^a-z0-9]"), "")

enum class ModsCatalogType { POKEMON, OBJECTS }

private data class ModsCatalogEntry(
    val id: Int,
    val label: String,
    val alternative: String = "",
    val verifiedName: Boolean = true,
)


// Game data stores Pokémon names by INTERNAL species ID, not National Dex index.
// Decode the installed game data rather than guessing ID offsets for event Pokémon.
private val gamePokemonCipher = mapOf(
    'v' to 'B',
    '\\' to 'u',
    '=' to 'l',
    '"' to 'b',
    '}' to 'a',
    'G' to 's',
    'M' to 'r',
    ';' to 'I',
    '*' to 'v',
    '&' to 'y',
    ']' to 'V',
    'u' to 'e',
    '1' to 'n',
    'L' to 'C',
    'z' to 'h',
    'i' to 'm',
    'Y' to 'd',
    'W' to 'o',
    '6' to 'i',
    '?' to 'z',
    '+' to 'S',
    '{' to 'q',
    'A' to 't',
    'D' to 'W',
    '7' to 'p',
    'g' to 'M',
    '!' to 'f',
    'j' to 'K',
    'F' to 'k',
    '$' to 'P',
    'I' to 'g',
    'R' to 'R',
    '3' to 'c',
    'Z' to 'w',
    't' to 'F',
    '>' to 'E',
    '@' to 'A',
    '(' to 'N',
    'C' to 'x',
    'H' to 'J',
    '8' to 'Z',
    'U' to 'G',
    'V' to 'O',
    '/' to 'D',
    ':' to 'T',
    's' to 'L',
    'y' to 'H',
    'k' to 'U',
    'E' to 'Y',
    'm' to 'Q',
    '[' to 'X',
    '^' to 'j',
    '4' to ' ',
    'x' to '-',
    'w' to '2',
    '\'' to '\'',
    'l' to '?',
)

private fun gamePokemonEntries(gameRoot: File): List<ModsCatalogEntry> {
    val names = File(gameRoot, "data/text/es/txt_pkmn.dll")
    if (!names.isFile) return emptyList()
    return names.bufferedReader(Charsets.ISO_8859_1).useLines { lines ->
        lines.take(1025).mapIndexedNotNull { index, raw ->
            if (raw.isBlank() || raw.length > 120) null
            else ModsCatalogEntry(index + 1, raw.map { c -> gamePokemonCipher[c] ?: c }.joinToString(""))
        }.toList()
    }
}
// Game-specific item indices are bundled from the 1.9.2.2 item list;
// they must never be replaced with IDs from FireRed, Emerald or PokéAPI.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModsCatalogScreen(
    type: ModsCatalogType,
    onBack: () -> Unit,
    onSelect: (Int) -> Unit,
) {
    val context = LocalContext.current
    val entries = remember(type) {
        if (type == ModsCatalogType.POKEMON) {
            runCatching {
                gamePokemonEntries(File(context.filesDir, "game"))
            }.getOrDefault(emptyList())
        } else {
            runCatching {
                context.assets.open("items_reloaded_catalog.csv").bufferedReader().useLines { lines ->
                    lines.mapNotNull { line ->
                        val parts = line.split('|', limit = 2)
                        val number = parts.firstOrNull()?.toIntOrNull()
                        if (parts.size != 2 || number == null || number !in 1..821) null
                        else ModsCatalogEntry(number, parts[1])
                    }.toList()
                }
            }.getOrDefault(emptyList())
        }
    }
    var query by remember(type) { mutableStateOf("") }
    var ballsOnly by remember(type) { mutableStateOf(false) }
    val filtered = remember(entries, query, ballsOnly, type) {
        val value = searchable(query.trim())
        entries.filter { entry ->
            (!ballsOnly || entry.id in 1..14) &&
                (value.isEmpty() || entry.id.toString().contains(value) ||
                    searchable(entry.label).contains(value) ||
                    searchable(entry.alternative).contains(value))
        }
    }
    val isPokemon = type == ModsCatalogType.POKEMON
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (isPokemon) "IDs de Pokémon" else "IDs de objetos") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                    }
                },
            )
        },
        contentWindowInsets = WindowInsets(0.dp),
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                if (isPokemon)
                    "IDs internos de Pokémon Reloaded obtenidos directamente de sus archivos instalados. Ejemplo: Cosmog es #980 (no #789). Seleccioná un Pokémon para copiar su ID al generador."
                else
                    "821 objetos de Pokémon Reloaded 1.9.2.2 con sus nombres e IDs. RADITEM solo admite objetos comunes y Poké Balls; no todos los objetos del catálogo pueden generarse.",
                style = MaterialTheme.typography.bodySmall,
            )
            OutlinedTextField(
                value = query,
                onValueChange = { query = it.take(50) },
                label = { Text(if (isPokemon) "Buscar Pokémon por nombre o número" else "Buscar objeto por nombre o ID") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            if (!isPokemon) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = ballsOnly,
                        onClick = { ballsOnly = !ballsOnly },
                        label = { Text("Poké Balls") },
                    )
                    FilterChip(
                        selected = !ballsOnly,
                        onClick = { ballsOnly = false },
                        label = { Text("Todos los IDs") },
                    )
                }
            }
            if (isPokemon && entries.isEmpty()) {
                Text("Primero importá el juego: no encuentro su lista de Pokémon.",
                    style = MaterialTheme.typography.bodyMedium)
            }
            Text(
                "${filtered.size} resultado(s) · Tocá «Usar ID» para llevarlo al generador.",
                style = MaterialTheme.typography.labelMedium,
            )
            LazyColumn(modifier = Modifier.weight(1f)) {
                items(filtered, key = { it.id }) { entry ->
                    ListItem(
                        headlineContent = {
                            Text("#${entry.id} · ${entry.label}")
                        },
                        supportingContent = {
                            Text(
                                if (isPokemon) "ID interno del juego · RADPK / RADSH"
                                else "Índice de objetos de Pokémon Reloaded 1.9.2.2"
                            )
                        },
                        trailingContent = {
                            TextButton(onClick = { onSelect(entry.id) }) {
                                Text("Usar ID")
                            }
                        },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
