package com.ruben.festtime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ruben.festtime.data.FestivalEvent
import com.ruben.festtime.data.Shift

@Composable
fun FestTimeScreen(viewModel: FestTimeViewModel) {
    val state by viewModel.uiState.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    listOf(Color(0xFFFCF5E5), Color(0xFFF5F9FC))
                )
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        HeaderBlock(
            state = state,
            onFestivalSelected = viewModel::selectFestival,
            onAlertsChanged = viewModel::setAlertsEnabled,
            onToggleFavorites = viewModel::toggleFavoritesOnly
        )

        FestivalFilters(
            state = state,
            onDaySelected = viewModel::selectDay,
            onShiftSelected = viewModel::selectShift,
            onStageSelected = viewModel::selectStage,
            onSearchChanged = viewModel::updateSearch
        )

        if (state.errorMessage != null) {
            Text(
                text = state.errorMessage ?: "",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(state.filteredEvents, key = { it.id }) { event ->
                EventRow(
                    event = event,
                    isFavorite = state.favorites.contains(event.id),
                    stageColorHex = state.currentBundle?.stageColors?.get(event.escenario),
                    onToggleFavorite = { viewModel.toggleFavorite(event.id) }
                )
            }
        }
    }
}

@Composable
private fun HeaderBlock(
    state: FestTimeUiState,
    onFestivalSelected: (String) -> Unit,
    onAlertsChanged: (Boolean) -> Unit,
    onToggleFavorites: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = Color.Transparent
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    Brush.horizontalGradient(listOf(Color(0xFFFFE29A), Color(0xFFFF719A)))
                )
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = "FestTime Android",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1A1A1A)
            )

            FestivalSelector(
                state = state,
                onFestivalSelected = onFestivalSelected
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text = "Avisos", color = Color(0xFF1A1A1A))
                    Switch(
                        checked = state.alertsEnabled,
                        onCheckedChange = onAlertsChanged
                    )
                }

                TextButton(onClick = onToggleFavorites) {
                    Text(if (state.showFavoritesOnly) "Ver todos" else "Solo favoritos")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FestivalSelector(
    state: FestTimeUiState,
    onFestivalSelected: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = state.festivals.firstOrNull { it.id == state.selectedFestivalId }?.name
        ?: "Selecciona festival"

    Box {
        AssistChip(
            onClick = { expanded = true },
            label = { Text(selectedName) }
        )

        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            state.festivals.forEach { festival ->
                DropdownMenuItem(
                    text = { Text("${festival.name} ${festival.year}") },
                    onClick = {
                        expanded = false
                        onFestivalSelected(festival.id)
                    }
                )
            }
        }
    }
}

@Composable
private fun FestivalFilters(
    state: FestTimeUiState,
    onDaySelected: (String) -> Unit,
    onShiftSelected: (Shift) -> Unit,
    onStageSelected: (String) -> Unit,
    onSearchChanged: (String) -> Unit
) {
    val bundle = state.currentBundle ?: return

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            bundle.festival.days.forEach { day ->
                FilterChip(
                    selected = day.id == state.selectedDayId,
                    onClick = { onDaySelected(day.id) },
                    label = { Text(day.displayName) }
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val forcedShift = bundle.festival.forcedShiftByDay[state.selectedDayId]
            val shifts = if (forcedShift == null) listOf(Shift.dia, Shift.noche) else listOf(forcedShift)
            shifts.forEach { shift ->
                FilterChip(
                    selected = shift == state.selectedShift,
                    onClick = { onShiftSelected(shift) },
                    label = { Text(shift.name.replaceFirstChar { it.uppercase() }) }
                )
            }
        }

        StageSelector(
            selected = state.selectedStage,
            availableStages = state.availableStages,
            onStageSelected = onStageSelected
        )

        OutlinedTextField(
            value = state.searchText,
            onValueChange = onSearchChanged,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Buscar artista") }
        )
    }
}

@Composable
private fun StageSelector(
    selected: String,
    availableStages: List<String>,
    onStageSelected: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        AssistChip(
            onClick = { expanded = true },
            label = { Text(if (selected == "todos") "Todos los escenarios" else selected) }
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("Todos") },
                onClick = {
                    expanded = false
                    onStageSelected("todos")
                }
            )
            availableStages.forEach { stage ->
                DropdownMenuItem(
                    text = { Text(stage) },
                    onClick = {
                        expanded = false
                        onStageSelected(stage)
                    }
                )
            }
        }
    }
}

@Composable
private fun EventRow(
    event: FestivalEvent,
    isFavorite: Boolean,
    stageColorHex: String?,
    onToggleFavorite: () -> Unit
) {
    val stripeColor = parseHex(stageColorHex)

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .padding(end = 10.dp)
                        .background(stripeColor)
                        .size(width = 6.dp, height = 52.dp)
                )
                Column {
                    Text(event.hora, fontWeight = FontWeight.SemiBold)
                    Text(event.artista, style = MaterialTheme.typography.titleMedium)
                    Text(event.escenario, style = MaterialTheme.typography.bodySmall)
                }
            }

            TextButton(onClick = onToggleFavorite) {
                Text(if (isFavorite) "Quitar" else "Fav")
            }
        }
    }
}

private fun parseHex(raw: String?): Color {
    if (raw.isNullOrBlank()) {
        return Color(0xFFCAD8E3)
    }
    return runCatching {
        Color(android.graphics.Color.parseColor(raw))
    }.getOrDefault(Color(0xFFCAD8E3))
}
