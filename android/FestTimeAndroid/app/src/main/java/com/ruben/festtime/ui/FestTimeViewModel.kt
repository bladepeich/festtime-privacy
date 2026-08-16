package com.ruben.festtime.ui

import android.app.Application
import android.content.Context
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
    val isRefreshingFestivals: Boolean = false,
    val lastRemoteSyncAtMillis: Long? = null,
    val infoMessage: String? = null,
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

            if (showFavoritesOnly) {
                val dayOrder = bundle.festival.days
                    .mapIndexed { index, day -> day.id to index }
                    .toMap()

                return bundle.events
                    .filter { favorites.contains(it.id) }
                    .sortedWith(
                        compareBy<FestivalEvent>(
                            { dayOrder[it.dia] ?: Int.MAX_VALUE },
                            { it.sortableMinutes },
                            { it.artista.lowercase() }
                        )
                    )
            }

            val base = bundle.events
                .filter { it.dia == selectedDayId && it.turno == selectedShift }
                .filter { selectedStage == "todos" || it.escenario == selectedStage }
                .filter { searchText.isBlank() || it.searchArtist.contains(searchText.trim().lowercase()) }

            return base.sortedWith(compareBy<FestivalEvent>({ it.sortableMinutes }, { it.artista.lowercase() }))
        }
}

class FestTimeViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = FestivalRepository(application)
    private val remoteFeedService = RemoteFestivalFeedService(application)
    private val store = FavoritesStore(application)
    private val reminderScheduler = ReminderScheduler(application)
    private val runtimePrefs = application.getSharedPreferences(RUNTIME_PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(
        FestTimeUiState(
            lastRemoteSyncAtMillis = runtimePrefs.takeIf { it.contains(LAST_REMOTE_SYNC_AT_KEY) }
                ?.getLong(LAST_REMOTE_SYNC_AT_KEY, 0L)
                ?.takeIf { it > 0L }
        )
    )
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
            markRemoteSyncSuccess()
            loadCatalogFromRepository(showErrors = false)
        }
    }

    fun refreshFestivals() {
        viewModelScope.launch {
            if (_uiState.value.isRefreshingFestivals) {
                return@launch
            }

            val selectedFestivalId = _uiState.value.selectedFestivalId
            _uiState.update { it.copy(isRefreshingFestivals = true, infoMessage = null, errorMessage = null) }

            runCatching {
                withContext(Dispatchers.IO) {
                    val syncedFestivals = remoteFeedService.syncFromRemote()
                    val festivals = repository.loadCatalog().sortedByDescending { festivalSortDate(it) }
                    val keepSelection = selectedFestivalId.isNotBlank() && festivals.any { it.id == selectedFestivalId }

                    if (!keepSelection) {
                        return@withContext RefreshResult(
                            syncedFestivals = syncedFestivals,
                            festivals = festivals,
                            selectedFestivalId = "",
                            selectedBundle = null,
                            favorites = emptySet(),
                            alertsEnabled = false,
                            selectedDayId = "",
                            selectedShift = Shift.noche
                        )
                    }

                    val bundle = repository.loadBundle(selectedFestivalId)
                    val favorites = store.getFavorites(selectedFestivalId)
                    val firstDay = bundle.festival.defaultDayId
                    val firstShift = bundle.festival.forcedShiftByDay[firstDay] ?: bundle.festival.defaultShift

                    RefreshResult(
                        syncedFestivals = syncedFestivals,
                        festivals = festivals,
                        selectedFestivalId = selectedFestivalId,
                        selectedBundle = bundle,
                        favorites = favorites,
                        alertsEnabled = store.areAlertsEnabled(selectedFestivalId),
                        selectedDayId = firstDay,
                        selectedShift = firstShift
                    )
                }
            }.onSuccess { result ->
                markRemoteSyncSuccess()
                _uiState.update {
                    it.copy(
                        festivals = result.festivals,
                        selectedFestivalId = result.selectedFestivalId,
                        currentBundle = result.selectedBundle,
                        selectedDayId = result.selectedDayId,
                        selectedShift = result.selectedShift,
                        selectedStage = "todos",
                        searchText = "",
                        showFavoritesOnly = false,
                        favorites = result.favorites,
                        alertsEnabled = result.alertsEnabled,
                        infoMessage = "Actualizados ${result.syncedFestivals} festivales",
                        errorMessage = null
                    )
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(infoMessage = null, errorMessage = error.message ?: "No se pudo actualizar el catalogo remoto")
                }
            }.also {
                _uiState.update { it.copy(isRefreshingFestivals = false) }
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
                        infoMessage = null,
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
        val state = _uiState.value
        val festivalId = state.selectedFestivalId
        if (festivalId.isBlank()) {
            return
        }

        val updated = state.favorites.toMutableSet().apply {
            if (contains(eventId)) remove(eventId) else add(eventId)
        }

        _uiState.update { it.copy(favorites = updated) }

        viewModelScope.launch(Dispatchers.IO) {
            store.saveFavorites(festivalId, updated)
        }

        val currentBundle = state.currentBundle
        if (state.alertsEnabled && currentBundle != null) {
            viewModelScope.launch(Dispatchers.IO) {
                reminderScheduler.scheduleForFestival(currentBundle, updated)
            }
        }
    }

    fun setAlertsEnabled(enabled: Boolean) {
        val festivalId = _uiState.value.selectedFestivalId
        val bundle = _uiState.value.currentBundle ?: return

        viewModelScope.launch(Dispatchers.IO) {
            store.setAlertsEnabled(festivalId, enabled)
        }
        _uiState.update { it.copy(alertsEnabled = enabled) }

        if (!enabled) {
            viewModelScope.launch(Dispatchers.IO) {
                reminderScheduler.cancelForFestival(festivalId)
            }
            return
        }

        val favorites = _uiState.value.favorites
        viewModelScope.launch(Dispatchers.IO) {
            reminderScheduler.scheduleForFestival(bundle, favorites)
        }
    }

    fun rescheduleReminders() {
        val state = _uiState.value
        val bundle = state.currentBundle ?: return
        if (!state.alertsEnabled) {
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            reminderScheduler.scheduleForFestival(bundle, state.favorites)
        }
    }

    private fun festivalSortDate(festival: FestivalDefinition): LocalDate {
        return festival.days
            .mapNotNull { day -> day.calendarDate?.let { runCatching { LocalDate.parse(it) }.getOrNull() } }
            .minOrNull()
            ?: LocalDate.of(festival.year, 1, 1)
    }

    private fun markRemoteSyncSuccess() {
        val now = System.currentTimeMillis()
        runtimePrefs.edit().putLong(LAST_REMOTE_SYNC_AT_KEY, now).apply()
        _uiState.update { it.copy(lastRemoteSyncAtMillis = now) }
    }

    companion object {
        private const val RUNTIME_PREFS_NAME = "festtime_runtime"
        private const val LAST_REMOTE_SYNC_AT_KEY = "festtime.lastRemoteSyncAt"
    }

    private data class RefreshResult(
        val syncedFestivals: Int,
        val festivals: List<FestivalDefinition>,
        val selectedFestivalId: String,
        val selectedBundle: FestivalBundle?,
        val favorites: Set<String>,
        val alertsEnabled: Boolean,
        val selectedDayId: String,
        val selectedShift: Shift
    )
}
