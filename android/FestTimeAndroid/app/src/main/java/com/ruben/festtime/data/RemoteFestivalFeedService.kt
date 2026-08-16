package com.ruben.festtime.data

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
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
        val incomingFestivalIds = payload.festivals.map { it.festival.id }.toSet()
        val existingBundleFiles = cacheDir.listFiles().orEmpty().filter { it.name.endsWith(".bundle.json") }
        val existingFestivalIds = existingBundleFiles.map { it.name.removeSuffix(".bundle.json") }.toSet()

        var updatedOrInserted = 0
        payload.festivals.forEach { remoteFestival ->
            val incomingBundle = FestivalBundle(
                festival = remoteFestival.festival,
                stageColors = remoteFestival.stageColors,
                events = remoteFestival.events
            )

            val existingFile = File(cacheDir, "${remoteFestival.festival.id}.bundle.json")
            val hasChanged = if (!existingFile.exists()) {
                true
            } else {
                val previous = runCatching {
                    json.decodeFromString<FestivalBundle>(existingFile.readText())
                }.getOrNull()
                previous != incomingBundle
            }

            if (hasChanged) {
                updatedOrInserted += 1
            }
        }

        val removedFestivals = existingFestivalIds.subtract(incomingFestivalIds).size

        if (payload.fullReplace || payload.festivals.isEmpty()) {
            cacheDir.listFiles()?.forEach { file ->
                if (file.name.endsWith(".bundle.json") || file.name == "festivals-catalog.json") {
                    file.delete()
                }
            }
        }

        val catalog = FestivalCatalog(festivals = payload.festivals.map { it.festival })
        File(cacheDir, "festivals-catalog.json").writeText(json.encodeToString(catalog))

        // Remove stale bundles that no longer exist in the remote feed.
        cacheDir.listFiles()?.forEach { file ->
            if (!file.name.endsWith(".bundle.json")) {
                return@forEach
            }
            val festivalId = file.name.removeSuffix(".bundle.json")
            if (festivalId !in incomingFestivalIds) {
                file.delete()
            }
        }

        payload.festivals.forEach { remoteFestival ->
            val bundle = FestivalBundle(
                festival = remoteFestival.festival,
                stageColors = remoteFestival.stageColors,
                events = remoteFestival.events
            )
            File(cacheDir, "${remoteFestival.festival.id}.bundle.json").writeText(json.encodeToString(bundle))
        }

        return updatedOrInserted + removedFestivals
    }

    private fun fetchRemoteFeed(url: String): RemoteFeedPayload {
        val requestURL = withCacheBusting(url)
        val connection = (URL(requestURL).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 12_000
            useCaches = false
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Cache-Control", "no-cache, no-store, max-age=0")
            setRequestProperty("Pragma", "no-cache")
        }

        return try {
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            json.decodeFromString<RemoteFeedPayload>(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun withCacheBusting(url: String): String {
        val separator = if (url.contains("?")) "&" else "?"
        val ts = URLEncoder.encode(System.currentTimeMillis().toString(), StandardCharsets.UTF_8.toString())
        return "$url${separator}ft_sync_ts=$ts"
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
