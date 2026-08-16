package com.ruben.festtime.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.ruben.festtime.data.FestivalRepository
import com.ruben.festtime.data.FavoritesStore
import kotlin.concurrent.thread

class BootRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        thread(start = true) {
            val repository = FestivalRepository(appContext)
            val store = FavoritesStore(appContext)
            val scheduler = ReminderScheduler(appContext)

            val festivals = runCatching { repository.loadCatalog() }.getOrDefault(emptyList())
            festivals.forEach { festival ->
                if (!store.areAlertsEnabled(festival.id)) {
                    return@forEach
                }

                val favorites = store.getFavorites(festival.id)
                if (favorites.isEmpty()) {
                    scheduler.cancelForFestival(festival.id)
                    return@forEach
                }

                val bundle = runCatching { repository.loadBundle(festival.id) }.getOrNull() ?: return@forEach
                scheduler.scheduleForFestival(bundle, favorites)
            }
        }
    }
}
