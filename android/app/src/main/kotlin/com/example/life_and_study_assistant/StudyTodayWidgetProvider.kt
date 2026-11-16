package com.example.life_and_study_assistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

/** Mistakes waiting, reviews due and accuracy — the three numbers worth a glance. */
class StudyTodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            StudyWidgetSync.ACTION_REFRESH -> {
                val mgr = AppWidgetManager.getInstance(context)
                for (id in ids(context)) {
                    val views = RemoteViews(context.packageName, R.layout.widget_study_today)
                    views.setTextViewText(
                        R.id.study_sync_time,
                        StudyWidgetSync.busyHeader(context)
                    )
                    mgr.partiallyUpdateAppWidget(id, views)
                }
                // Dart recollects and calls back through updateStudyWidgets. If
                // it cannot be reached, put the last snapshot back rather than
                // leaving the ellipsis sitting there forever.
                if (!StudyWidgetSync.request(context)) refreshAll(context)
            }
            StudyWidgetSync.ACTION_UPDATE_DATA -> refreshAll(context)
        }
    }

    companion object {
        private fun ids(context: Context): IntArray {
            val mgr = AppWidgetManager.getInstance(context)
            return mgr.getAppWidgetIds(
                ComponentName(context, StudyTodayWidgetProvider::class.java)
            )
        }

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            for (id in ids(context)) render(context, mgr, id)
        }

        fun render(context: Context, mgr: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_study_today)
            val prefs = StudyWidgetSync.prefs(context)

            // Written as Bengali numerals by Dart so the widget reads like the
            // rest of the app; an absent key means the app has not run since
            // the widget was added, so show a dash, not a misleading zero.
            views.setTextViewText(
                R.id.study_wrong_value,
                prefs.getString("flutter.study_wrong_count_text", null) ?: "—"
            )
            views.setTextViewText(
                R.id.study_due_value,
                prefs.getString("flutter.study_due_count_text", null) ?: "—"
            )
            views.setTextViewText(
                R.id.study_accuracy_value,
                prefs.getString("flutter.study_accuracy_text", null) ?: "—"
            )
            views.setTextViewText(
                R.id.study_weak_topics,
                prefs.getString("flutter.study_weak_topics", null)
                    ?: "অ্যাপ খুললে হিসাব আসবে"
            )
            views.setTextViewText(
                R.id.study_sync_time,
                prefs.getString("flutter.study_widget_sync_time", null) ?: ""
            )

            views.setOnClickPendingIntent(
                R.id.study_root,
                WidgetIntents.openApp(context, "/mistake_notebook", requestCode = 10)
            )
            views.setOnClickPendingIntent(
                R.id.study_btn_refresh,
                WidgetIntents.broadcast(
                    context,
                    StudyTodayWidgetProvider::class.java,
                    StudyWidgetSync.ACTION_REFRESH,
                    requestCode = 11
                )
            )

            mgr.updateAppWidget(appWidgetId, views)
        }
    }
}

/** PendingIntents, built the same way for every study widget. */
object WidgetIntents {
    private fun flags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    fun openApp(context: Context, route: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("route", route)
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags())
    }

    fun broadcast(
        context: Context,
        target: Class<*>,
        action: String,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(context, target).apply { this.action = action }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags())
    }

    /**
     * As [broadcast], carrying one int.
     *
     * Each needs its own requestCode: PendingIntents that match on everything
     * but their extras are the same PendingIntent to Android, so four options
     * sharing a code would all deliver whichever extra was registered last.
     */
    fun broadcastWithExtra(
        context: Context,
        target: Class<*>,
        action: String,
        extraName: String,
        extraValue: Int,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(context, target).apply {
            this.action = action
            putExtra(extraName, extraValue)
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags())
    }
}
