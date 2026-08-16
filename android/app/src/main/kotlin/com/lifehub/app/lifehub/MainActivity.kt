package com.lifehub.app.lifehub

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "lifehub/course_shortcut"
    private val shareChannelName = "lifehub/share_capture"
    private val widgetChannelName = "lifehub/widgets"
    private var channel: MethodChannel? = null
    private var shareChannel: MethodChannel? = null
    private var pendingDestination: String? = null
    private var pendingShare: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingDestination = destinationFrom(intent)
        pendingShare = sharedTextFrom(intent)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCourseShortcut" -> result.success(requestCourseShortcut())
                    "requestCourseWidget" -> result.success(requestCourseWidget())
                    "consumeInitialDestination" -> {
                        val destination = pendingDestination
                        pendingDestination = null
                        result.success(destination)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shareChannelName,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeInitialShare" -> {
                        val value = pendingShare
                        pendingShare = null
                        result.success(value)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            widgetChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "updateWidgets") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val values = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
            val editor = getSharedPreferences(WIDGET_PREFERENCES, MODE_PRIVATE).edit()
            values.forEach { (key, value) ->
                when (value) {
                    is Int -> editor.putInt(key.toString(), value)
                    is Long -> editor.putLong(key.toString(), value)
                    is String -> editor.putString(key.toString(), value)
                    is Boolean -> editor.putBoolean(key.toString(), value)
                }
            }
            editor.apply()
            CourseWidgetProvider.updateAll(this)
            TodayWidgetProvider.updateAll(this)
            result.success(true)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lifehub/attachments",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = (call.arguments as? Map<*, *>)?.get("path") as? String
            result.success(openAttachment(path))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        destinationFrom(intent)?.let { destination ->
            val currentChannel = channel
            if (currentChannel == null) {
                pendingDestination = destination
            } else {
                currentChannel.invokeMethod("openDestination", destination)
            }
        }
        sharedTextFrom(intent)?.let { value ->
            val currentShareChannel = shareChannel
            if (currentShareChannel == null) {
                pendingShare = value
            } else {
                currentShareChannel.invokeMethod("sharedText", value)
            }
        }
    }

    private fun requestCourseShortcut(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unsupported"
        val manager = getSystemService(ShortcutManager::class.java)
        if (!manager.isRequestPinShortcutSupported) return "unsupported"
        val openCourses = Intent(this, MainActivity::class.java).apply {
            action = ACTION_OPEN_COURSES
            putExtra(EXTRA_DESTINATION, DESTINATION_COURSES)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val shortcut = ShortcutInfo.Builder(this, COURSE_SHORTCUT_ID)
            .setShortLabel("课程表")
            .setLongLabel("打开 LifeHub 课程表")
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(openCourses)
            .build()
        return if (manager.requestPinShortcut(shortcut, null)) {
            "requested"
        } else {
            "failed"
        }
    }

    private fun requestCourseWidget(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unsupported"
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) return "unsupported"
        val provider = ComponentName(this, CourseWidgetProvider::class.java)
        val preview = RemoteViews(packageName, R.layout.widget_course_preview)
        val extras = Bundle().apply {
            putParcelable(AppWidgetManager.EXTRA_APPWIDGET_PREVIEW, preview)
        }
        val callbackIntent = Intent(this, CourseWidgetPinReceiver::class.java)
        val callback = PendingIntent.getBroadcast(
            this,
            COURSE_WIDGET_CALLBACK_ID,
            callbackIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return if (manager.requestPinAppWidget(provider, extras, callback)) {
            "requested"
        } else {
            "failed"
        }
    }

    private fun openAttachment(path: String?): String {
        if (path.isNullOrBlank()) return "missing"
        val file = File(path)
        if (!file.exists()) return "missing"
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val extension = file.extension.lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(packageManager) == null) return "no_handler"
        startActivity(intent)
        return "opened"
    }

    private fun destinationFrom(intent: Intent?): String? {
        if (intent?.action != ACTION_OPEN_COURSES) return null
        return intent.getStringExtra(EXTRA_DESTINATION) ?: DESTINATION_COURSES
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
    }

    companion object {
        private const val ACTION_OPEN_COURSES =
            "com.lifehub.app.lifehub.action.OPEN_COURSES"
        private const val EXTRA_DESTINATION = "destination"
        private const val DESTINATION_COURSES = "courses"
        private const val COURSE_SHORTCUT_ID = "lifehub_course_timetable"
        private const val COURSE_WIDGET_CALLBACK_ID = 4003
        const val WIDGET_PREFERENCES = "lifehub_widget_snapshot"
    }
}
