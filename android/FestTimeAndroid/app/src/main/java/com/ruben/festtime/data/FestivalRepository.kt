package com.ruben.festtime.data

import android.content.Context
import kotlinx.serialization.json.Json

class FestivalRepository(private val context: Context) {

    private val json = Json {
        ignoreUnknownKeys = true
    }

    fun loadCatalog(): List<FestivalDefinition> {
        val content = context.assets.open("festivals/festivals-catalog.json")
            .bufferedReader()
            .use { it.readText() }
        return json.decodeFromString<FestivalCatalog>(content).festivals
    }

    fun loadBundle(festivalId: String): FestivalBundle {
        val content = context.assets.open("festivals/$festivalId.bundle.json")
            .bufferedReader()
            .use { it.readText() }
        return json.decodeFromString(content)
    }
}
