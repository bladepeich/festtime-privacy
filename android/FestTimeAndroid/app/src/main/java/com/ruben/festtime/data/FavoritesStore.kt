package com.ruben.festtime.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class FavoritesStore(context: Context) {

    private val prefs: SharedPreferences = createPrefs(context)

    private fun createPrefs(context: Context): SharedPreferences {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (_: Exception) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    fun getFavorites(festivalId: String): Set<String> {
        return prefs.getStringSet(favoritesKey(festivalId), emptySet()) ?: emptySet()
    }

    fun saveFavorites(festivalId: String, favorites: Set<String>) {
        prefs.edit().putStringSet(favoritesKey(festivalId), favorites).apply()
    }

    fun areAlertsEnabled(festivalId: String): Boolean {
        return prefs.getBoolean(alertsKey(festivalId), false)
    }

    fun setAlertsEnabled(festivalId: String, enabled: Boolean) {
        prefs.edit().putBoolean(alertsKey(festivalId), enabled).apply()
    }

    private fun favoritesKey(festivalId: String) = "festtime.favorites.$festivalId"

    private fun alertsKey(festivalId: String) = "festtime.alerts.$festivalId"

    companion object {
        const val PREFS_NAME = "festtime_prefs"
    }
}
