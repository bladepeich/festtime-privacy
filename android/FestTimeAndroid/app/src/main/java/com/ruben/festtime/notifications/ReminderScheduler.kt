package com.ruben.festtime.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.ruben.festtime.data.FestivalBundle
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class ReminderScheduler(private val context: Context) {

    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val offsets = listOf(15, 10, 5)

    fun scheduleForFestival(bundle: FestivalBundle, favorites: Set<String>) {
        cancelForFestival(bundle.festival.id)

        val dayDateMap = bundle.festival.days.associate { it.id to it.calendarDate }
        val now = LocalDateTime.now()

        bundle.events
            .filter { favorites.contains(it.id) }
            .forEach { event ->
                val date = dayDateMap[event.dia] ?: return@forEach
                val start = eventStartDateTime(date, event.hora) ?: return@forEach

                offsets.forEach { offset ->
                    val reminderTime = start.minusMinutes(offset.toLong())
                    if (reminderTime.isAfter(now)) {
                        scheduleReminder(
                            festivalId = bundle.festival.id,
                            eventId = event.id,
                            artist = event.artista,
                            stage = event.escenario,
                            reminderDateTime = reminderTime,
                            offset = offset
                        )
                    }
                }
            }
    }

    fun cancelForFestival(festivalId: String) {
        for (code in 0 until 10000) {
            val requestCode = requestCode(festivalId, code)
            val intent = Intent(context, FavoriteReminderReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            ) ?: continue
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun scheduleReminder(
        festivalId: String,
        eventId: String,
        artist: String,
        stage: String,
        reminderDateTime: LocalDateTime,
        offset: Int
    ) {
        val idSuffix = "$eventId-$offset"
        val notificationId = kotlin.math.abs(idSuffix.hashCode())
        val requestCode = requestCode(festivalId, notificationId % 10000)

        val intent = Intent(context, FavoriteReminderReceiver::class.java).apply {
            putExtra(FavoriteReminderReceiver.EXTRA_TITLE, "$artist empieza en $offset min")
            putExtra(FavoriteReminderReceiver.EXTRA_BODY, stage)
            putExtra(FavoriteReminderReceiver.EXTRA_NOTIFICATION_ID, notificationId)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerAtMillis = reminderDateTime
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()

        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            pendingIntent
        )
    }

    private fun requestCode(festivalId: String, value: Int): Int {
        return kotlin.math.abs((festivalId.hashCode() * 31) + value)
    }

    private fun eventStartDateTime(rawDate: String, rawTime: String): LocalDateTime? {
        val date = runCatching {
            LocalDate.parse(rawDate, DateTimeFormatter.ISO_LOCAL_DATE)
        }.getOrNull() ?: return null

        val timeText = rawTime.substringBefore(" ").trim()
        val split = timeText.split(":")
        if (split.size != 2) {
            return null
        }

        val hour = split[0].toIntOrNull() ?: return null
        val minute = split[1].toIntOrNull() ?: return null
        val adjustedHour = if (hour < 10) hour + 24 else hour

        val normalizedDate = if (adjustedHour >= 24) date.plusDays(1) else date
        val normalizedHour = adjustedHour % 24
        val time = LocalTime.of(normalizedHour, minute)

        return LocalDateTime.of(normalizedDate, time)
    }
}
