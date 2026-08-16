package com.ruben.festtime.ui

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import com.ruben.festtime.R
import com.ruben.festtime.WebViewActivity
import com.ruben.festtime.data.FestivalEvent
import com.ruben.festtime.data.FestivalDefinition
import com.ruben.festtime.data.FestivalMenuOption
import com.ruben.festtime.data.Shift
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.text.Normalizer

@Composable
fun FestTimeScreen(viewModel: FestTimeViewModel) {
    val state by viewModel.uiState.collectAsState()

    if (state.currentBundle == null || state.selectedFestivalId.isBlank()) {
        WelcomeScreen(state = state, onSelectFestival = viewModel::selectFestival)
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF2F2F7))
    ) {
        TopControlsBar(
            state = state,
            onFestivalSelected = viewModel::selectFestival,
            onRefreshFestivals = viewModel::refreshFestivals,
            onAlertsChanged = viewModel::setAlertsEnabled,
            onToggleFavorites = viewModel::toggleFavoritesOnly
        )

        HeaderBlock(state = state)

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
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = 10.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (state.filteredEvents.isEmpty()) {
                item {
                    Text(
                        text = "Horarios no Disponibles",
                        color = Color(0xFF6B7280),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 20.dp)
                    )
                }
            }

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
private fun WelcomeScreen(
    state: FestTimeUiState,
    onSelectFestival: (String) -> Unit
) {
    val context = LocalContext.current
    val screenWidth = LocalConfiguration.current.screenWidthDp
    val horizontalPadding = if (screenWidth >= 420) 42.dp else 24.dp
    val logoHeight = if (screenWidth >= 420) 168.dp else 132.dp
    var showPicker by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                brush = Brush.linearGradient(
                    listOf(Color(0xFF0D2433), Color(0xFF1E2D43))
                )
            )
            .padding(horizontal = horizontalPadding, vertical = 28.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Image(
                painter = painterResource(id = R.drawable.festtime_logo),
                contentDescription = "FestTime",
                modifier = Modifier
                    .fillMaxWidth()
                    .height(logoHeight),
                contentScale = ContentScale.Fit
            )

            Button(
                onClick = { showPicker = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color.Black
                )
            ) {
                Text("Seleccionar festival", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
            }

            Text(
                text = "En colaboracion con:",
                color = Color.White.copy(alpha = 0.92f),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold
            )

            Image(
                painter = painterResource(id = R.drawable.lcda_logo_light),
                contentDescription = "La Chica de Ayer",
                modifier = Modifier
                    .fillMaxWidth()
                    .height(if (screenWidth >= 420) 86.dp else 74.dp),
                contentScale = ContentScale.Fit
            )

            Button(
                onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://lachicadeayer.news"))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White.copy(alpha = 0.94f),
                    contentColor = Color.Black
                )
            ) {
                Text("Ir a la revista", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
            }
        }
    }

    if (showPicker) {
        FestivalPickerDialog(
            state = state,
            onDismiss = { showPicker = false },
            onSelectFestival = {
                showPicker = false
                onSelectFestival(it)
            }
        )
    }
}

@Composable
private fun FestivalPickerDialog(
    state: FestTimeUiState,
    onDismiss: () -> Unit,
    onSelectFestival: (String) -> Unit
) {
    val groupedFestivals = remember(state.festivals) { buildFestivalMonthGroups(state.festivals) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Festivales") },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                groupedFestivals.forEach { group ->
                    item(key = "month-${group.key}") {
                        Text(
                            text = group.label,
                            style = MaterialTheme.typography.labelMedium,
                            color = Color(0xFF6B7280),
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(top = 4.dp)
                        )
                    }

                    items(group.festivals, key = { it.id }) { festival ->
                        Button(
                            onClick = { onSelectFestival(festival.id) },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(10.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color(0xFFF3F4F6),
                                contentColor = Color.Black
                            )
                        ) {
                            Text(festival.name)
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cerrar")
            }
        }
    )
}

@Composable
private fun TopControlsBar(
    state: FestTimeUiState,
    onFestivalSelected: (String) -> Unit,
    onRefreshFestivals: () -> Unit,
    onAlertsChanged: (Boolean) -> Unit,
    onToggleFavorites: () -> Unit
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val screenWidth = LocalConfiguration.current.screenWidthDp
    val favoritesWidth = if (screenWidth >= 420) 160.dp else 132.dp
    val logoHeight = if (screenWidth >= 420) 52.dp else 42.dp
    var menuExpanded by remember { mutableStateOf(false) }
    var showPicker by remember { mutableStateOf(false) }
    var pendingEnableAlerts by remember { mutableStateOf(false) }
    val selectedFestival = state.festivals.firstOrNull { it.id == state.selectedFestivalId }
    val notificationsCount = if (state.alertsEnabled) state.favorites.size else 0

    val notificationsPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted && pendingEnableAlerts) {
            onAlertsChanged(true)
        }
        pendingEnableAlerts = false
    }

    LaunchedEffect(state.alertsEnabled) {
        if (state.alertsEnabled) {
            pendingEnableAlerts = false
        }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Button(
            onClick = onToggleFavorites,
            modifier = Modifier.width(favoritesWidth),
            shape = RoundedCornerShape(999.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (state.showFavoritesOnly) Color(0xFFF6D74A) else Color.White,
                contentColor = Color.Black
            ),
            border = BorderStroke(1.dp, Color(0xFFE2E4E9)),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Icon(
                imageVector = if (state.showFavoritesOnly) Icons.Filled.Star else Icons.Outlined.Star,
                contentDescription = null
            )
            Text("Favoritos", fontWeight = FontWeight.Bold, maxLines = 1)
        }

        Spacer(modifier = Modifier.width(8.dp))

        Image(
            painter = painterResource(id = R.drawable.festtime_logo),
            contentDescription = "FestTime",
            modifier = Modifier
                .weight(1f)
                .height(logoHeight),
            contentScale = ContentScale.Fit
        )

        Spacer(modifier = Modifier.width(8.dp))

        Box {
            IconButton(
                onClick = { menuExpanded = true },
                modifier = Modifier
                    .size(if (screenWidth >= 420) 46.dp else 40.dp)
                    .clip(CircleShape)
                    .background(Color.White)
            ) {
                Icon(Icons.Filled.Menu, contentDescription = "Menu", tint = Color.Black)
            }

            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                DropdownMenuItem(
                    text = { Text("Seleccionar Festival") },
                    onClick = {
                        menuExpanded = false
                        showPicker = true
                    }
                )

                DropdownMenuItem(
                    text = { Text("Actualizar Festivales") },
                    onClick = {
                        menuExpanded = false
                        onRefreshFestivals()
                    }
                )

                DropdownMenuItem(
                    text = { Text(if (state.alertsEnabled) "Desactivar Notificaciones" else "Activar Notificaciones") },
                    onClick = {
                        menuExpanded = false
                        if (state.alertsEnabled) {
                            onAlertsChanged(false)
                            return@DropdownMenuItem
                        }

                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            onAlertsChanged(true)
                            return@DropdownMenuItem
                        }

                        val hasPermission = ContextCompat.checkSelfPermission(
                            context,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED

                        if (hasPermission) {
                            onAlertsChanged(true)
                        } else {
                            pendingEnableAlerts = true
                            if (activity != null) {
                                notificationsPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            }
                        }
                    }
                )

                DropdownMenuItem(
                    text = { Text("Notificaciones ($notificationsCount)") },
                    onClick = { menuExpanded = false }
                )

                HorizontalDivider()

                selectedFestival?.let { festival ->
                    DropdownMenuItem(
                        text = { Text(festival.name) },
                        enabled = false,
                        onClick = { menuExpanded = false }
                    )

                    orderedMenuOptions(festival.menuOptions).forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option.title) },
                            onClick = {
                                menuExpanded = false
                                val url = option.inAppImageURL ?: option.url
                                if (!url.isNullOrBlank()) {
                                    if (shouldOpenInApp(option.title)) {
                                        val intent = Intent(context, WebViewActivity::class.java).apply {
                                            putExtra(WebViewActivity.EXTRA_TITLE, option.title)
                                            putExtra(WebViewActivity.EXTRA_URL, url)
                                        }
                                        context.startActivity(intent)
                                    } else {
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    if (showPicker) {
        FestivalPickerDialog(
            state = state,
            onDismiss = { showPicker = false },
            onSelectFestival = {
                showPicker = false
                onFestivalSelected(it)
            }
        )
    }
}

@Composable
private fun HeaderBlock(state: FestTimeUiState) {
    val selectedFestivalName = state.festivals.firstOrNull { it.id == state.selectedFestivalId }?.name

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                brush = Brush.linearGradient(
                    listOf(Color(0xFFE63946), Color(0xFF1D3557))
                )
            )
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (!selectedFestivalName.isNullOrBlank()) {
            Text(
                text = "Festival seleccionado: $selectedFestivalName",
                color = Color.White,
                fontWeight = FontWeight.Black
            )
        }

        Text(
            text = "Avisos y alarma para favoritos: 15, 10 y 5 min antes",
            style = MaterialTheme.typography.labelMedium,
            color = Color.White.copy(alpha = 0.9f)
        )
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

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(bundle.festival.days, key = { it.id }) { day ->
                CapsuleChip(
                    text = day.displayName,
                    selected = day.id == state.selectedDayId,
                    onClick = { onDaySelected(day.id) }
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            val forcedShift = bundle.festival.forcedShiftByDay[state.selectedDayId]
            val shifts = if (forcedShift == null) listOf(Shift.dia, Shift.noche) else listOf(forcedShift)
            shifts.forEach { shift ->
                Button(
                    onClick = { onShiftSelected(shift) },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(999.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (shift == state.selectedShift) Color(0xFFF6D74A) else Color.White,
                        contentColor = Color.Black
                    ),
                    border = BorderStroke(1.dp, Color(0xFFE2E4E9))
                ) {
                    Text(shift.name.replaceFirstChar { it.uppercase() }, fontWeight = FontWeight.Bold)
                }
            }
        }

        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                StageChip(
                    title = "Todos",
                    colorHex = "#495057",
                    selected = state.selectedStage == "todos",
                    onClick = { onStageSelected("todos") }
                )
            }

            items(state.availableStages, key = { it }) { stage ->
                StageChip(
                    title = stage,
                    colorHex = bundle.stageColors[stage] ?: "#6c757d",
                    selected = state.selectedStage == stage,
                    onClick = { onStageSelected(stage) }
                )
            }
        }

        OutlinedTextField(
            value = state.searchText,
            onValueChange = onSearchChanged,
            label = { Text("Buscar artista") },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = Color.White,
                unfocusedContainerColor = Color.White
            )
        )
    }
}

@Composable
private fun CapsuleChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        shape = RoundedCornerShape(999.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (selected) Color(0xFFF6D74A) else Color.White,
            contentColor = Color.Black
        ),
        border = BorderStroke(1.dp, Color(0xFFE2E4E9))
    ) {
        Text(text, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun StageChip(
    title: String,
    colorHex: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    val color = parseHex(colorHex)

    Button(
        onClick = onClick,
        shape = RoundedCornerShape(999.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (selected) color else Color.White,
            contentColor = if (selected) Color.White else color
        ),
        border = BorderStroke(1.5.dp, color)
    ) {
        Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        border = BorderStroke(1.dp, Color(0x14000000))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .padding(end = 10.dp)
                        .background(stripeColor)
                        .size(width = 6.dp, height = 60.dp)
                )

                Column {
                    Text("${event.hora} h", fontWeight = FontWeight.SemiBold)
                    Text(
                        text = event.artista,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = event.escenario,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = stripeColor
                    )
                }
            }

            IconButton(onClick = onToggleFavorite) {
                Icon(
                    imageVector = if (isFavorite) Icons.Filled.Star else Icons.Outlined.Star,
                    contentDescription = "Favorito",
                    tint = if (isFavorite) Color(0xFFFFC107) else Color(0xFF9CA3AF)
                )
            }
        }
    }
}

private fun orderedMenuOptions(options: List<FestivalMenuOption>): List<FestivalMenuOption> {
    val priority = mapOf(
        "web oficial" to 0,
        "entradas" to 1,
        "ubicacion recinto" to 2,
        "ubicacion del recinto" to 2,
        "plano del recinto" to 3
    )

    return options.sortedWith(compareBy<FestivalMenuOption> {
        priority[normalizeText(it.title)] ?: 100
    }.thenBy { it.title.lowercase() })
}

private fun normalizeText(value: String): String {
    return Normalizer.normalize(value, Normalizer.Form.NFD)
        .replace("\\p{M}+".toRegex(), "")
        .lowercase()
}

private data class FestivalMonthGroup(
    val key: String,
    val label: String,
    val festivals: List<FestivalDefinition>
)

private fun buildFestivalMonthGroups(festivals: List<FestivalDefinition>): List<FestivalMonthGroup> {
    val grouped = festivals.groupBy { festival ->
        festivalStartDate(festival)?.let { YearMonth.from(it) }
    }

    val monthFormatter = DateTimeFormatter.ofPattern("MMMM yyyy", Locale("es", "ES"))

    val datedGroups = grouped.entries
        .filter { it.key != null }
        .sortedByDescending { it.key }
        .map { entry ->
            val month = entry.key!!
            FestivalMonthGroup(
                key = month.toString(),
                label = month.atDay(1)
                    .format(monthFormatter)
                    .replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale("es", "ES")) else it.toString() },
                festivals = entry.value.sortedByDescending { festivalStartDate(it) }
            )
        }

    val undated = grouped[null].orEmpty()
    if (undated.isEmpty()) {
        return datedGroups
    }

    return datedGroups + FestivalMonthGroup(
        key = "sin-fecha",
        label = "Sin fecha",
        festivals = undated.sortedByDescending { it.year }
    )
}

private fun festivalStartDate(festival: FestivalDefinition): LocalDate? {
    return festival.days
        .mapNotNull { day -> day.calendarDate?.let { runCatching { LocalDate.parse(it) }.getOrNull() } }
        .minOrNull()
}

private fun shouldOpenInApp(rawTitle: String): Boolean {
    return when (normalizeText(rawTitle)) {
        "web oficial", "entradas" -> true
        else -> false
    }
}

private fun parseHex(raw: String?): Color {
    if (raw.isNullOrBlank()) {
        return Color(0xFF6C757D)
    }
    return runCatching {
        Color(android.graphics.Color.parseColor(raw))
    }.getOrDefault(Color(0xFF6C757D))
}
