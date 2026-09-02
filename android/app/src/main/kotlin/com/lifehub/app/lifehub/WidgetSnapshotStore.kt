package com.lifehub.app.lifehub

import android.content.Context
import org.json.JSONObject
import java.io.File

object WidgetSnapshotStore {
    private const val FILE_NAME = "lifehub_widget_snapshot.json"

    fun refreshPreferences(context: Context) {
        val file = File(context.filesDir, FILE_NAME)
        if (!file.isFile) return
        val snapshot = runCatching { JSONObject(file.readText()) }.getOrNull() ?: return
        val editor = context.getSharedPreferences(
            MainActivity.WIDGET_PREFERENCES,
            Context.MODE_PRIVATE,
        ).edit()
        snapshot.keys().forEach { key ->
            when (val value = snapshot.opt(key)) {
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Number -> editor.putLong(key, value.toLong())
                is String -> editor.putString(key, value)
                is Boolean -> editor.putBoolean(key, value)
            }
        }
        editor.apply()
    }
}
