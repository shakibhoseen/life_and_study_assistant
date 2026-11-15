package com.example.life_and_study_assistant

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * One question a day out of the mistake notebook.
 *
 * Revealing the answer is handled here rather than in Dart: it is a toggle on
 * a value already in preferences, and waking the engine to flip a boolean
 * would make a tap feel like a sync.
 */
class QuestionOfDayWidgetProvider : AppWidgetProvider() {

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
            ACTION_TOGGLE_ANSWER -> {
                val prefs = StudyWidgetSync.prefs(context)
                val revealed = prefs.getBoolean("flutter.study_qotd_revealed", false)
                prefs.edit().putBoolean("flutter.study_qotd_revealed", !revealed).apply()
                refreshAll(context)
            }
            StudyWidgetSync.ACTION_REFRESH ->
                if (!StudyWidgetSync.request(context)) refreshAll(context)
            StudyWidgetSync.ACTION_UPDATE_DATA -> refreshAll(context)
        }
    }

    companion object {
        const val ACTION_TOGGLE_ANSWER =
            "com.example.life_and_study_assistant.TOGGLE_QOTD_ANSWER"

        private val MARKERS = listOf("ক", "খ", "গ", "ঘ", "ঙ", "চ")

        private fun ids(context: Context): IntArray {
            val mgr = AppWidgetManager.getInstance(context)
            return mgr.getAppWidgetIds(
                ComponentName(context, QuestionOfDayWidgetProvider::class.java)
            )
        }

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            for (id in ids(context)) render(context, mgr, id)
        }

        /**
         * Splits the stored JSON array of options without pulling in a JSON
         * library: these are the app's own rows, written by Dart's jsonEncode.
         * A row that will not parse leaves the options blank rather than
         * throwing inside a RemoteViews update, which would drop the widget to
         * "Problem loading widget".
         */
        private fun parseOptions(json: String?): List<String> {
            if (json.isNullOrBlank()) return emptyList()
            return try {
                val arr = org.json.JSONArray(json)
                (0 until arr.length()).map { arr.optString(it) }
            } catch (_: Throwable) {
                emptyList()
            }
        }

        fun render(context: Context, mgr: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_question_of_day)
            val prefs = StudyWidgetSync.prefs(context)

            val question = prefs.getString("flutter.study_qotd_question", null)
            val options = parseOptions(prefs.getString("flutter.study_qotd_options", null))
            val correctIndex =
                StudyWidgetSync.int(context, "flutter.study_qotd_correct_index", -1)
            val revealed = prefs.getBoolean("flutter.study_qotd_revealed", false)

            views.setTextViewText(
                R.id.qotd_question,
                question ?: "অ্যাপ খুললে আজকের প্রশ্ন আসবে"
            )
            views.setTextViewText(
                R.id.qotd_options,
                options.mapIndexed { i, opt ->
                    "${MARKERS.getOrElse(i) { "•" }}) $opt"
                }.joinToString("\n")
            )

            if (revealed && correctIndex in options.indices) {
                views.setTextViewText(
                    R.id.qotd_answer,
                    "✓ ${MARKERS.getOrElse(correctIndex) { "" }}) ${options[correctIndex]}"
                )
                views.setInt(
                    R.id.qotd_answer,
                    "setBackgroundResource",
                    R.drawable.widget_answer_revealed
                )
            } else {
                views.setTextViewText(R.id.qotd_answer, "উত্তর দেখুন")
                views.setInt(
                    R.id.qotd_answer,
                    "setBackgroundResource",
                    R.drawable.widget_reveal_button
                )
            }

            views.setOnClickPendingIntent(
                R.id.qotd_answer,
                WidgetIntents.broadcast(
                    context,
                    QuestionOfDayWidgetProvider::class.java,
                    ACTION_TOGGLE_ANSWER,
                    requestCode = 30
                )
            )
            views.setOnClickPendingIntent(
                R.id.qotd_root,
                WidgetIntents.openApp(context, "/mistake_notebook", requestCode = 31)
            )
            views.setOnClickPendingIntent(
                R.id.qotd_btn_refresh,
                WidgetIntents.broadcast(
                    context,
                    QuestionOfDayWidgetProvider::class.java,
                    StudyWidgetSync.ACTION_REFRESH,
                    requestCode = 32
                )
            )

            mgr.updateAppWidget(appWidgetId, views)
        }
    }
}
