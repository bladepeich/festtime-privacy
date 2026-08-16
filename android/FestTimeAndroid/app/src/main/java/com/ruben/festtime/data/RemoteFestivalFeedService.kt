package com.ruben.festtime.data

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class RemoteFestivalFeedService(private val context: Context) {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val cacheDir: File by lazy {
        File(context.filesDir, "festivals-cache").apply { mkdirs() }
    }

    fun syncFromRemote(url: String = DEFAULT_REMOTE_FEED_URL): Int {
        val payload = fetchRemoteFeed(url)
        if (payload.festivals.isEmpty()) {
            return 0
        }

        if (payload.fullReplace) {
            cacheDir.listFiles()?.forEach { file ->
                if (file.name.endsWith(".bundle.json") || file.name == "festivals-catalog.json") {
                    file.delete()
                }
            }
        }

        val catalog = FestivalCatalog(festivals = payload.festivals.map { it.festival })
        File(cacheDir, "festivals-catalog.json").writeText(json.encodeToString(catalog))

        payload.festivals.forEach { remoteFestival ->
            val bundle = FestivalBundle(
                festival = remoteFestival.festival,
                stageColors = remoteFestival.stageColors,
                events = remoteFestival.events
            )
            File(cacheDir, "${remoteFestival.festival.id}.bundle.json").writeText(json.encodeToString(bundle))
        }

        return payload.festivals.size
    }

    private fun fetchRemoteFeed(url: String): RemoteFeedPayload {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 12_000
            setRequestProperty("Accept", "application/json")
        }

        return try {
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            json.decodeFromString<RemoteFeedPayload>(body)
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        const val DEFAULT_REMOTE_FEED_URL = "https://raw.githubusercontent.com/bladepeich/festtime-privacy/main/appstore/remote-festivals-feed.test-additions.json"
    }
}

@Serializable
private data class RemoteFeedPayload(
    val formatVersion: Int,
    val fullReplace: Boolean = false,
    val festivals: List<RemoteFestivalItem> = emptyList()
)

@Serializable
private data class RemoteFestivalItem(
    val revision: String,
    val festival: FestivalDefinition,
    val stageColors: Map<String, String> = emptyMap(),
    val events: List<FestivalEvent> = emptyList()
)
