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

enum class ModsCatalogType { POKEMON, OBJECTS }

private data class ModsCatalogEntry(
    val id: Int,
    val label: String,
    val alternative: String = "",
    val verifiedName: Boolean = true,
)

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
                context.assets.open("pokemon_catalog.csv").bufferedReader().useLines { lines ->
                    lines.mapNotNull { line ->
                        val parts = line.split('|', limit = 3)
                        val number = parts.firstOrNull()?.toIntOrNull()
                        if (parts.size < 3 || number == null || number !in 1..1025) null
                        else ModsCatalogEntry(number, parts[1], parts[2])
                    }.toList()
                }
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
        val value = query.trim().lowercase()
        entries.filter { entry ->
            (!ballsOnly || entry.id in 1..14) &&
                (value.isEmpty() || entry.id.toString().contains(value) ||
                    entry.label.lowercase().contains(value) ||
                    entry.alternative.lowercase().contains(value))
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
                    "1.025 especies · Números de Pokédex Nacional. Pokémon Reloaded puede usar índices internos distintos, especialmente para formas especiales; comprobá el resultado antes de guardar."
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
                                if (isPokemon) "Pokédex Nacional · Referencia"
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
