package com.ruben.festtime.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ruben.festtime.data.FestivalBundle
import com.ruben.festtime.data.FestivalDefinition
import com.ruben.festtime.data.FestivalEvent
import com.ruben.festtime.data.FavoritesStore
import com.ruben.festtime.data.FestivalRepository
import com.ruben.festtime.data.RemoteFestivalFeedService
import com.ruben.festtime.data.Shift
import com.ruben.festtime.notifications.ReminderScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import java.time.LocalDate

data class FestTimeUiState(
    val festivals: List<FestivalDefinition> = emptyList(),
    val selectedFestivalId: String = "",
    val currentBundle: FestivalBundle? = null,
    val selectedDayId: String = "",
    val selectedShift: Shift = Shift.noche,
    val selectedStage: String = "todos",
    val searchText: String = "",
    val showFavoritesOnly: Boolean = false,
    val favorites: Set<String> = emptySet(),
    val alertsEnabled: Boolean = false,
    val errorMessage: String? = null
) {
    val availableStages: List<String>
        get() {
            val bundle = currentBundle ?: return emptyList()
            return bundle.events
                .filter { it.dia == selectedDayId && it.turno == selectedShift }
                .map { it.escenario }
                .distinct()
                .sorted()
        }

    val filteredEvents: List<FestivalEvent>
        get() {
            val bundle = currentBundle ?: return emptyList()
            val base = bundle.events
                .filter { it.dia == selectedDayId && it.turno == selectedShift }
                .filter { selectedStage == "todos" || it.escenario == selectedStage }
                .filter { searchText.isBlank() || it.searchArtist.contains(searchText.trim().lowercase()) }
                .filter { !showFavoritesOnly || favorites.contains(it.id) }

            return base.sortedWith(compareBy<FestivalEvent>({ it.sortableMinutes }, { it.artista.lowercase() }))
        }
}

class FestTimeViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = FestivalRepository(application)
    private val remoteFeedService = RemoteFestivalFeedService(application)
    private val store = FavoritesStore(application)
    private val reminderScheduler = ReminderScheduler(application)

    private val _uiState = MutableStateFlow(FestTimeUiState())
    val uiState: StateFlow<FestTimeUiState> = _uiState

    init {
        loadCatalog()
    }

    fun loadCatalog() {
        viewModelScope.launch {
            loadCatalogFromRepository(showErrors = true)
            syncRemoteAndReload()
        }
    }

    private suspend fun loadCatalogFromRepository(showErrors: Boolean) {
        runCatching {
            withContext(Dispatchers.IO) { repository.loadCatalog() }
        }.onSuccess { festivals ->
            val sortedFestivals = festivals.sortedByDescending { festivalSortDate(it) }
            _uiState.update { current ->
                val keepCurrentFestival = sortedFestivals.any { it.id == current.selectedFestivalId }
                current.copy(
                    festivals = sortedFestivals,
                    selectedFestivalId = if (keepCurrentFestival) current.selectedFestivalId else "",
                    currentBundle = if (keepCurrentFestival) current.currentBundle else null,
                    errorMessage = null
                )
            }
        }.onFailure { error ->
            if (showErrors) {
                _uiState.update { it.copy(errorMessage = error.message ?: "No se pudo cargar el catalogo") }
            }
        }
    }

    private suspend fun syncRemoteAndReload() {
        runCatching {
            withContext(Dispatchers.IO) { remoteFeedService.syncFromRemote() }
        }.onSuccess {
            loadCatalogFromRepository(showErrors = false)
        }
    }

    fun refreshFestivals() {
        viewModelScope.launch {
            val selectedFestivalId = _uiState.value.selectedFestivalId

            runCatching {
                withContext(Dispatchers.IO) { remoteFeedService.syncFromRemote() }
            }.onSuccess {
                loadCatalogFromRepository(showErrors = true)
                if (selectedFestivalId.isNotBlank() && _uiState.value.festivals.any { it.id == selectedFestivalId }) {
                    selectFestival(selectedFestivalId)
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(errorMessage = error.message ?: "No se pudo actualizar el catalogo remoto")
                }
            }
        }
    }

    fun selectFestival(festivalId: String) {
        viewModelScope.launch {
            runCatching {
                repository.loadBundle(festivalId)
            }.onSuccess { bundle ->
                val favoriteSet = store.getFavorites(festivalId)
                val firstDay = bundle.festival.defaultDayId
                val firstShift = bundle.festival.forcedShiftByDay[firstDay] ?: bundle.festival.defaultShift
                _uiState.update {
                    it.copy(
                        selectedFestivalId = festivalId,
                        currentBundle = bundle,
                        selectedDayId = firstDay,
                        selectedShift = firstShift,
                        selectedStage = "todos",
                        searchText = "",
                        showFavoritesOnly = false,
                        favorites = favoriteSet,
                        alertsEnabled = store.areAlertsEnabled(festivalId),
                        errorMessage = null
                    )
                }
            }.onFailure { error ->
                _uiState.update { it.copy(errorMessage = error.message ?: "No se pudo cargar el festival") }
            }
        }
    }

    fun selectDay(dayId: String) {
        _uiState.update { state ->
            val forcedShift = state.currentBundle?.festival?.forcedShiftByDay?.get(dayId)
            state.copy(
                selectedDayId = dayId,
                selectedShift = forcedShift ?: state.selectedShift,
                selectedStage = "todos"
            )
        }
    }

    fun selectShift(shift: Shift) {
        _uiState.update { it.copy(selectedShift = shift, selectedStage = "todos") }
    }

    fun selectStage(stage: String) {
        _uiState.update { it.copy(selectedStage = stage) }
    }

    fun updateSearch(text: String) {
        _uiState.update { it.copy(searchText = text) }
    }

    fun toggleFavoritesOnly() {
        _uiState.update { it.copy(showFavoritesOnly = !it.showFavoritesOnly) }
    }

    fun toggleFavorite(eventId: String) {
        val festivalId = _uiState.value.selectedFestivalId
        if (festivalId.isBlank()) {
            return
        }

        val updated = _uiState.value.favorites.toMutableSet().apply {
            if (contains(eventId)) remove(eventId) else add(eventId)
        }

        store.saveFavorites(festivalId, updated)
        _uiState.update { it.copy(favorites = updated) }

        if (_uiState.value.alertsEnabled) {
            rescheduleReminders()
        }
    }

    fun setAlertsEnabled(enabled: Boolean) {
        val festivalId = _uiState.value.selectedFestivalId
        val bundle = _uiState.value.currentBundle ?: return

        store.setAlertsEnabled(festivalId, enabled)
        _uiState.update { it.copy(alertsEnabled = enabled) }

        if (!enabled) {
            reminderScheduler.cancelForFestival(festivalId)
            return
        }

        reminderScheduler.scheduleForFestival(bundle, _uiState.value.favorites)
    }

    fun rescheduleReminders() {
        val state = _uiState.value
        val bundle = state.currentBundle ?: return
        if (!state.alertsEnabled) {
            return
        }
        reminderScheduler.scheduleForFestival(bundle, state.favorites)
    }

    private fun festivalSortDate(festival: FestivalDefinition): LocalDate {
        return festival.days
            .mapNotNull { day -> day.calendarDate?.let { runCatching { LocalDate.parse(it) }.getOrNull() } }
            .minOrNull()
            ?: LocalDate.of(festival.year, 1, 1)
    }
}
