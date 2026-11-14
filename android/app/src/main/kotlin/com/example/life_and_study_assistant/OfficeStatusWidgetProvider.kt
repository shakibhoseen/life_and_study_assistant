package com.example.life_and_study_assistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import java.text.SimpleDateFormat
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
        if (intent.action == ACTION_REFRESH_WIDGET || intent.action == ACTION_UPDATE_DATA) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, OfficeStatusWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
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

            // 1. Attendance Data
            val checkInDate = prefs.getString("flutter.pref_last_check_in_date", "")
            val checkInTime = prefs.getString("flutter.pref_last_check_in_time", "")
            val isLate = prefs.getBoolean("flutter.pref_last_check_in_is_late", false)

            val checkOutDate = prefs.getString("flutter.pref_last_check_out_date", "")
            val checkOutTime = prefs.getString("flutter.pref_last_check_out_time", "")

            val isCheckedOutToday = checkOutDate == todayIso && !checkOutTime.isNullOrEmpty()
            val isCheckedInToday = checkInDate == todayIso && !checkInTime.isNullOrEmpty()

            if (isCheckedOutToday) {
                views.setTextViewText(R.id.widget_punch_icon, "🚪")
                views.setTextViewText(R.id.widget_punch_title, "Checked Out: $checkOutTime")
                views.setTextViewText(R.id.widget_punch_subtitle, "Workday Completed ✓ Have a relaxing evening!")
                views.setInt(R.id.widget_attendance_container, "setBackgroundResource", R.drawable.widget_punch_pending)
            } else if (isCheckedInToday) {
                val lateLabel = if (isLate) "(Late)" else "(On-Time ✓)"
                views.setTextViewText(R.id.widget_punch_icon, "🟢")
                views.setTextViewText(R.id.widget_punch_title, "Check-In: $checkInTime $lateLabel")
                views.setTextViewText(R.id.widget_punch_subtitle, "Workday: In Progress • 9h Target 6:00 PM")
                views.setInt(R.id.widget_attendance_container, "setBackgroundResource", R.drawable.widget_punch_success)
            } else {
                views.setTextViewText(R.id.widget_punch_icon, "⏳")
                views.setTextViewText(R.id.widget_punch_title, "Not Checked In Today")
                views.setTextViewText(R.id.widget_punch_subtitle, "Connect to Office Wi-Fi to Punch In")
                views.setInt(R.id.widget_attendance_container, "setBackgroundResource", R.drawable.widget_punch_pending)
            }

            // 2. Lunch Serving Status
            val lunchStatus = prefs.getString("flutter.pref_last_notified_lunch_status", "cooking")?.lowercase() ?: "cooking"
            val customLunchBadge = when (lunchStatus) {
                "served" -> "Served 🍽️"
                "received" -> "Arrived 🏢"
                "upcoming" -> "On Way 🚗"
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
                "received" -> views.setInt(R.id.widget_step_received, "setBackgroundResource", R.drawable.widget_stepper_active)
                "upcoming" -> views.setInt(R.id.widget_step_upcoming, "setBackgroundResource", R.drawable.widget_stepper_active)
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
