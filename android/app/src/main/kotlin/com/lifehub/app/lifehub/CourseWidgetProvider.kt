package com.lifehub.app.lifehub

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CourseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { update(context, appWidgetManager, it) }
    }

    companion object {
        fun update(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val preferences = context.getSharedPreferences(
                MainActivity.WIDGET_PREFERENCES,
                Context.MODE_PRIVATE,
            )
            val entries = preferences.getString("courseEntriesJson", null)
            val now = System.currentTimeMillis()
            val dayFormat = SimpleDateFormat("yyyyMMdd", Locale.getDefault())
            val today = dayFormat.format(Date(now))
            val upcoming = if (entries == null) {
                emptyList()
            } else {
                runCatching {
                    val array = JSONArray(entries)
                    (0 until array.length())
                        .map { array.getJSONObject(it) }
                        .filter { it.optLong("endAt") > now }
                        .filter {
                            dayFormat.format(Date(it.optLong("startAt"))) == today
                        }
                        .sortedBy { it.optLong("startAt") }
                        .take(2)
                }.getOrDefault(emptyList())
            }
            val views = RemoteViews(context.packageName, R.layout.widget_course)
            if (upcoming.isEmpty()) {
                views.setTextViewText(R.id.widget_course_title, "今天暂无后续课程")
                views.setTextViewText(R.id.widget_course_detail, "")
                views.setViewVisibility(R.id.widget_course_second, View.GONE)
            } else {
                val first = upcoming[0]
                views.setTextViewText(R.id.widget_course_title, first.optString("title"))
                views.setTextViewText(R.id.widget_course_detail, detail(first))
                if (upcoming.size > 1) {
                    val second = upcoming[1]
                    views.setViewVisibility(R.id.widget_course_second, View.VISIBLE)
                    views.setTextViewText(
                        R.id.widget_course_second_title,
                        second.optString("title"),
                    )
                    views.setTextViewText(
                        R.id.widget_course_second_detail,
                        detail(second),
                    )
                } else {
                    views.setViewVisibility(R.id.widget_course_second, View.GONE)
                }
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "com.lifehub.app.lifehub.action.OPEN_COURSES"
                putExtra("destination", "courses")
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pending = PendingIntent.getActivity(
                context,
                4001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_course_root, pending)
            manager.updateAppWidget(widgetId, views)
        }

        private fun detail(entry: org.json.JSONObject): String {
            val time = SimpleDateFormat("HH:mm", Locale.getDefault())
                .format(Date(entry.optLong("startAt")))
            return listOf(
                time,
                entry.optString("teacher"),
                entry.optString("room"),
            ).filter { it.isNotBlank() }.joinToString(" · ")
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, CourseWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach {
                update(context, manager, it)
            }
        }
    }
}
