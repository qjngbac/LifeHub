package com.lifehub.app.lifehub

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TodayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { update(context, appWidgetManager, it) }
    }

    companion object {
        private fun update(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val preferences = context.getSharedPreferences(
                MainActivity.WIDGET_PREFERENCES,
                Context.MODE_PRIVATE,
            )
            fun number(key: String): Int =
                (preferences.all[key] as? Number)?.toInt() ?: 0
            val taskCount = number("taskCount")
            val habitDone = number("habitDone")
            val habitTotal = number("habitTotal")
            var event = preferences.getString("nextEventTitle", "").orEmpty()
            var eventTime = preferences.getString("nextEventTime", "").orEmpty()
            val entries = preferences.getString("eventEntriesJson", null)
            if (entries != null) {
                event = ""
                eventTime = ""
                val now = System.currentTimeMillis()
                val next = runCatching {
                    val array = JSONArray(entries)
                    (0 until array.length())
                        .map { array.getJSONObject(it) }
                        .filter { it.optLong("endAt") > now }
                        .minByOrNull { it.optLong("startAt") }
                }.getOrNull()
                if (next != null) {
                    event = next.optString("title")
                    eventTime = SimpleDateFormat("HH:mm", Locale.getDefault())
                        .format(Date(next.optLong("startAt")))
                }
            }
            val views = RemoteViews(context.packageName, R.layout.widget_today)
            views.setTextViewText(R.id.widget_today_tasks, "待办 $taskCount")
            views.setTextViewText(
                R.id.widget_today_habits,
                "习惯 $habitDone/$habitTotal",
            )
            views.setTextViewText(
                R.id.widget_today_event,
                if (event.isBlank()) "今天暂无后续日程" else "$eventTime $event",
            )
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pending = PendingIntent.getActivity(
                context,
                4002,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_today_root, pending)
            manager.updateAppWidget(widgetId, views)
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TodayWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach {
                update(context, manager, it)
            }
        }
    }
}
