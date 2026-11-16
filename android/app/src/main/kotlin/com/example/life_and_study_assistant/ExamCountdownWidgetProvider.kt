package com.example.life_and_study_assistant

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** How long until the next scheduled exam. */
class ExamCountdownWidgetProvider : AppWidgetProvider() {

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
                // Something has to change the instant it is tapped, or the
                // refresh reads as broken: collecting is fast and usually
                // produces the same figures, so the repaint looks identical.
                val mgr = AppWidgetManager.getInstance(context)
                for (id in ids(context)) {
                    val views = RemoteViews(context.packageName, R.layout.widget_exam_countdown)
                    views.setTextViewText(R.id.exam_sync_time, "⟳")
                    mgr.partiallyUpdateAppWidget(id, views)
                }
                if (!StudyWidgetSync.request(context)) refreshAll(context)
            }
            StudyWidgetSync.ACTION_UPDATE_DATA -> refreshAll(context)
        }
    }

    companion object {
        private fun ids(context: Context): IntArray {
            val mgr = AppWidgetManager.getInstance(context)
            return mgr.getAppWidgetIds(
                ComponentName(context, ExamCountdownWidgetProvider::class.java)
            )
        }

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            for (id in ids(context)) render(context, mgr, id)
        }

        fun render(context: Context, mgr: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_exam_countdown)
            val prefs = StudyWidgetSync.prefs(context)

            val title = prefs.getString("flutter.study_exam_title", null)
            if (title.isNullOrEmpty()) {
                views.setTextViewText(R.id.exam_countdown, "—")
                views.setTextViewText(R.id.exam_title, "অ্যাপ খুললে হিসাব আসবে")
                views.setTextViewText(R.id.exam_subtitle, "")
            } else {
                // Dart has already decided the wording — "আজ", "আগামীকাল",
                // "৩ দিন বাকি" — because that is a calendar-day judgement and
                // belongs with the data, not in the rendering.
                views.setTextViewText(
                    R.id.exam_countdown,
                    prefs.getString("flutter.study_exam_countdown", null) ?: "—"
                )
                views.setTextViewText(R.id.exam_title, title)
                views.setTextViewText(
                    R.id.exam_subtitle,
                    prefs.getString("flutter.study_exam_when", null) ?: ""
                )
            }

            views.setTextViewText(
                R.id.exam_sync_time,
                prefs.getString("flutter.study_widget_sync_time", null) ?: ""
            )

            views.setOnClickPendingIntent(
                R.id.exam_root,
                WidgetIntents.openApp(context, "/live_mcq", requestCode = 20)
            )
            views.setOnClickPendingIntent(
                R.id.exam_btn_refresh,
                WidgetIntents.broadcast(
                    context,
                    ExamCountdownWidgetProvider::class.java,
                    StudyWidgetSync.ACTION_REFRESH,
                    requestCode = 21
                )
            )

            mgr.updateAppWidget(appWidgetId, views)
        }
    }
}
