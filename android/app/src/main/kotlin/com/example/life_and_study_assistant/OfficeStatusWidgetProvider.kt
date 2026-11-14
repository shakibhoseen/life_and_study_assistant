package com.example.life_and_study_assistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class OfficeStatusWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, OfficeStatusWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)

        if (intent.action == ACTION_REFRESH_WIDGET) {
            // 1. Immediately provide visual feedback on all widgets
            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.widget_office_status)
                views.setTextViewText(R.id.widget_sync_time, "Syncing... ⏳")
                appWidgetManager.partiallyUpdateAppWidget(appWidgetId, views)
            }

            // 2. If app engine is active in memory, perform immediate sub-second Flutter sync
            if (MainActivity.activeChannel != null) {
                MainActivity.requestWidgetRefresh()
            } else {
                // 3. App is closed / suspended: enqueue WorkManager one-off background task
                try {
                    val data = Data.Builder()
                        .putString(
                            BackgroundWorker.DART_TASK_KEY,
                            "com.example.life_and_study_assistant.widget_sync"
                        )
                        .putString(
                            "dev.fluttercommunity.workmanager.UNIQUE_NAME",
                            "widget_sync_${System.currentTimeMillis()}"
                        )
                        .build()

                    val syncRequest = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                        .setInputData(data)
                        .build()

                    WorkManager.getInstance(context).enqueueUniqueWork(
                        "widget_refresh_task",
                        ExistingWorkPolicy.REPLACE,
                        syncRequest
                    )
                } catch (e: Throwable) {
                    // Fallback to repaint cached values
                    for (appWidgetId in appWidgetIds) {
                        updateAppWidget(context, appWidgetManager, appWidgetId)
                    }
                }
            }
        } else if (intent.action == ACTION_UPDATE_DATA) {
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }

    companion object {
        const val ACTION_REFRESH_WIDGET = "com.example.life_and_study_assistant.REFRESH_WIDGET"
        const val ACTION_UPDATE_DATA = "com.example.life_and_study_assistant.UPDATE_WIDGET_DATA"

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, OfficeStatusWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }

        private fun calculateNineHourTarget(checkInTimeStr: String): String {
            return try {
                val cleaned = checkInTimeStr.trim()
                val formats = arrayOf(
                    SimpleDateFormat("h:mm:ss a", Locale.ENGLISH),
                    SimpleDateFormat("h:mm a", Locale.ENGLISH),
                    SimpleDateFormat("HH:mm:ss", Locale.ENGLISH),
                    SimpleDateFormat("HH:mm", Locale.ENGLISH)
                )
                var date: Date? = null
                for (fmt in formats) {
                    try {
                        date = fmt.parse(cleaned)
                        if (date != null) break
                    } catch (_: Exception) {}
                }
                if (date != null) {
                    val cal = Calendar.getInstance()
                    cal.time = date
                    cal.add(Calendar.HOUR_OF_DAY, 9)
                    val outFmt = SimpleDateFormat("h:mm a", Locale.ENGLISH)
                    outFmt.format(cal.time)
                } else {
                    "6:00 PM"
                }
            } catch (_: Exception) {
                "6:00 PM"
            }
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_office_status)

            // Read Flutter's shared preferences
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val todayIso = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
            val timeFmt = SimpleDateFormat("h:mm a", Locale.getDefault())

            val isSim = prefs.getBoolean("flutter.packly_simulation_mode", false)

            // 1. Attendance Data - Check widget keys, then real keys, then simulation keys
            val checkInDate = prefs.getString("flutter.pref_last_check_in_date", "")?.takeIf { it.isNotEmpty() }
                ?: if (isSim) prefs.getString("flutter.simulated_check_in_date", "") else prefs.getString("flutter.last_checkin_date", "")

            val checkInTime = prefs.getString("flutter.pref_last_check_in_time", "")?.takeIf { it.isNotEmpty() }
                ?: if (isSim) prefs.getString("flutter.simulated_check_in_time", "") else prefs.getString("flutter.packly_last_checkin_time", "")

            val isLate = if (prefs.contains("flutter.pref_last_check_in_is_late")) {
                prefs.getBoolean("flutter.pref_last_check_in_is_late", false)
            } else if (isSim) {
                prefs.getBoolean("flutter.simulated_check_in_is_late", false)
            } else {
                prefs.getBoolean("flutter.packly_last_checkin_is_late", false)
            }

            val checkOutDate = prefs.getString("flutter.pref_last_check_out_date", "")?.takeIf { it.isNotEmpty() }
                ?: if (isSim) prefs.getString("flutter.simulated_check_out_date", "") else prefs.getString("flutter.last_checkout_date", "")

            val checkOutTime = prefs.getString("flutter.pref_last_check_out_time", "")?.takeIf { it.isNotEmpty() }
                ?: if (isSim) prefs.getString("flutter.simulated_check_out_time", "") else prefs.getString("flutter.packly_last_checkout_time", "")

            val isCheckedOutToday = (checkOutDate == todayIso || checkOutDate?.startsWith(todayIso) == true) && !checkOutTime.isNullOrEmpty()
            val isCheckedInToday = (checkInDate == todayIso || checkInDate?.startsWith(todayIso) == true) && !checkInTime.isNullOrEmpty()

            if (isCheckedOutToday) {
                views.setTextViewText(R.id.widget_punch_icon, "🚪")
                views.setTextViewText(R.id.widget_punch_title, "Checked Out: $checkOutTime")
                views.setTextViewText(R.id.widget_punch_subtitle, "Workday Completed ✓ Have a relaxing evening!")
                views.setInt(R.id.widget_attendance_container, "setBackgroundResource", R.drawable.widget_punch_pending)
            } else if (isCheckedInToday) {
                val lateLabel = if (isLate) "(Late)" else "(On-Time ✓)"
                val targetNineHours = calculateNineHourTarget(checkInTime ?: "")
                views.setTextViewText(R.id.widget_punch_icon, "🟢")
                views.setTextViewText(R.id.widget_punch_title, "Check-In: $checkInTime $lateLabel")
                views.setTextViewText(R.id.widget_punch_subtitle, "Workday: In Progress • 9h Target $targetNineHours")
                views.setInt(R.id.widget_attendance_container, "setBackgroundResource", R.drawable.widget_punch_success)
            } else {
                views.setTextViewText(R.id.widget_punch_icon, "⏳")
                views.setTextViewText(R.id.widget_punch_title, "Not Checked In Today")
                views.setTextViewText(R.id.widget_punch_subtitle, "Connect to Office Wi-Fi to Punch In")
                views.setInt(R.id.widget_attendance_container, "setBackgroundResource", R.drawable.widget_punch_pending)
            }

            // 2. Lunch Serving Status
            val lunchStatusRaw = prefs.getString("flutter.pref_last_notified_lunch_status", "")?.takeIf { it.isNotEmpty() }
                ?: if (isSim) prefs.getString("flutter.simulated_serving_status", "") else prefs.getString("flutter.last_notified_lunch_status", "")
            val lunchStatus = lunchStatusRaw?.lowercase()?.ifEmpty { "cooking" } ?: "cooking"

            val customLunchBadge = when (lunchStatus) {
                "served" -> "Served 🍽️"
                "received", "car_reached" -> "Arrived 🏢"
                "upcoming", "on_the_way" -> "On Way 🚗"
                else -> "Cooking 🍳"
            }
            views.setTextViewText(R.id.widget_lunch_status_badge, customLunchBadge)

            // Reset all 4 steps to inactive
            views.setInt(R.id.widget_step_cooking, "setBackgroundResource", R.drawable.widget_stepper_inactive)
            views.setInt(R.id.widget_step_upcoming, "setBackgroundResource", R.drawable.widget_stepper_inactive)
            views.setInt(R.id.widget_step_received, "setBackgroundResource", R.drawable.widget_stepper_inactive)
            views.setInt(R.id.widget_step_served, "setBackgroundResource", R.drawable.widget_stepper_inactive)

            // Highlight the active step
            when (lunchStatus) {
                "served" -> views.setInt(R.id.widget_step_served, "setBackgroundResource", R.drawable.widget_stepper_active)
                "received", "car_reached" -> views.setInt(R.id.widget_step_received, "setBackgroundResource", R.drawable.widget_stepper_active)
                "upcoming", "on_the_way" -> views.setInt(R.id.widget_step_upcoming, "setBackgroundResource", R.drawable.widget_stepper_active)
                else -> views.setInt(R.id.widget_step_cooking, "setBackgroundResource", R.drawable.widget_stepper_active)
            }

            // 3. Header Sync Time
            val currentSyncTime = prefs.getString("flutter.widget_last_sync_time", timeFmt.format(Date()))
            views.setTextViewText(R.id.widget_sync_time, currentSyncTime)

            // 4. Tap Widget -> Open App directly to MainActivity
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val appIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("route", "/office_portal")
            }
            val appPendingIntent = PendingIntent.getActivity(context, 0, appIntent, flags)
            views.setOnClickPendingIntent(R.id.widget_root, appPendingIntent)

            // 5. Tap Refresh Button -> Trigger Refresh
            val refreshIntent = Intent(context, OfficeStatusWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_WIDGET
            }
            val refreshPendingIntent = PendingIntent.getBroadcast(context, 1, refreshIntent, flags)
            views.setOnClickPendingIntent(R.id.widget_btn_refresh, refreshPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
