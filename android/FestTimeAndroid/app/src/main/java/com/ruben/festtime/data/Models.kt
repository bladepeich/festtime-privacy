package com.ruben.festtime.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class FestivalCatalog(
    val festivals: List<FestivalDefinition>
)

@Serializable
data class FestivalDefinition(
    val id: String,
    @SerialName("legacyIDs") val legacyIds: List<String> = emptyList(),
    val name: String,
    val year: Int,
    val days: List<FestivalDay>,
    @SerialName("defaultDayID") val defaultDayId: String,
    val defaultShift: Shift,
    val forcedShiftByDay: Map<String, Shift> = emptyMap(),
    @SerialName("favoriteIDAliases") val favoriteIdAliases: Map<String, String> = emptyMap(),
    val menuOptions: List<FestivalMenuOption> = emptyList(),
    val eventsFile: String,
    val stageColorsFile: String
)

@Serializable
data class FestivalMenuOption(
    val title: String,
    val url: String? = null,
    val inAppImageURL: String? = null,
    val systemImage: String? = null
)

@Serializable
data class FestivalDay(
    val id: String,
    val displayName: String,
    val calendarDate: String? = null
)

@Serializable
enum class Shift {
    dia,
    noche
}

@Serializable
data class FestivalEvent(
    val id: String,
    val dia: String,
    val turno: Shift,
    val hora: String,
    val artista: String,
    val escenario: String
) {
    val searchArtist: String
        get() = artista.lowercase()

    val sortableMinutes: Int
        get() {
            val firstToken = hora.substringBefore(" ").trim()
            val split = firstToken.split(":")
            if (split.size != 2) {
                return Int.MAX_VALUE
            }
            val hour = split[0].toIntOrNull() ?: return Int.MAX_VALUE
            val minute = split[1].toIntOrNull() ?: return Int.MAX_VALUE
            return if (hour < 10) {
                (hour + 24) * 60 + minute
            } else {
                hour * 60 + minute
            }
        }
}

@Serializable
data class FestivalBundle(
    val festival: FestivalDefinition,
    val stageColors: Map<String, String>,
    val events: List<FestivalEvent>
)
