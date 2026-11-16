package com.example.life_and_study_assistant

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * One question at a time out of the mistake notebook, answerable in place.
 *
 * Everything here happens natively, on preferences Dart filled in earlier: the
 * question, the options, which one is right, and a short queue of the ones
 * after it. A tap on a home screen has to land at once, and waking a Flutter
 * engine to check an answer or fetch the next question would make it feel
 * broken.
 *
 * Answering here deliberately does **not** touch the mistake bank, the
 * attempt counts or the accuracy figure. A stray tap on a home screen is easy,
 * and study records are not something a misfire should be able to edit. The
 * drill inside the app is what counts; this is for recognising a question and
 * moving on.
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
        val prefs = StudyWidgetSync.prefs(context)
        when (intent.action) {
            ACTION_ANSWER -> {
                val picked = intent.getIntExtra(EXTRA_OPTION, -1)
                prefs.edit().putInt(KEY_PICKED, picked).apply()
                refreshAll(context)
            }
            ACTION_REVEAL -> {
                val revealed = prefs.getBoolean(KEY_REVEALED, false)
                prefs.edit().putBoolean(KEY_REVEALED, !revealed).apply()
                refreshAll(context)
            }
            ACTION_NEXT -> {
                val queue = readQueue(context)
                if (queue.isNotEmpty()) {
                    val cursor = StudyWidgetSync.int(context, KEY_CURSOR, 0)
                    prefs.edit()
                        .putInt(KEY_CURSOR, (cursor + 1) % queue.size)
                        // A new question starts clean: no pick, nothing shown.
                        .putInt(KEY_PICKED, -1)
                        .putBoolean(KEY_REVEALED, false)
                        .apply()
                }
                refreshAll(context)
            }
            StudyWidgetSync.ACTION_REFRESH -> {
                val mgr = AppWidgetManager.getInstance(context)
                for (id in ids(context)) {
                    val views = RemoteViews(context.packageName, R.layout.widget_question_of_day)
                    views.setTextViewText(
                        R.id.qotd_sync_time,
                        StudyWidgetSync.busyHeader(context)
                    )
                    mgr.partiallyUpdateAppWidget(id, views)
                }
                if (!StudyWidgetSync.request(context)) refreshAll(context)
            }
            StudyWidgetSync.ACTION_UPDATE_DATA -> refreshAll(context)
        }
    }

    companion object {
        const val ACTION_ANSWER = "com.example.life_and_study_assistant.QOTD_ANSWER"
        const val ACTION_REVEAL = "com.example.life_and_study_assistant.TOGGLE_QOTD_ANSWER"
        const val ACTION_NEXT = "com.example.life_and_study_assistant.QOTD_NEXT"
        const val EXTRA_OPTION = "option"

        private const val KEY_QUEUE = "flutter.study_qotd_queue"
        private const val KEY_CURSOR = "flutter.study_qotd_cursor"
        private const val KEY_PICKED = "flutter.study_qotd_picked"
        private const val KEY_REVEALED = "flutter.study_qotd_revealed"

        private val MARKERS = listOf("ক", "খ", "গ", "ঘ", "ঙ", "চ")
        private val OPTION_IDS = listOf(
            R.id.qotd_option_0,
            R.id.qotd_option_1,
            R.id.qotd_option_2,
            R.id.qotd_option_3
        )

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
         * The queue Dart left. A row that will not parse yields an empty list
         * rather than throwing: an exception in a widget provider kills the
         * receiver, and Android then tells the user to open the app.
         */
        private fun readQueue(context: Context): List<JSONObject> {
            val raw = StudyWidgetSync.prefs(context).getString(KEY_QUEUE, null)
                ?: return emptyList()
            return try {
                val arr = JSONArray(raw)
                (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }
            } catch (_: Throwable) {
                emptyList()
            }
        }

        private fun optionsOf(entry: JSONObject): List<String> {
            val arr = entry.optJSONArray("o") ?: return emptyList()
            return (0 until arr.length()).map { arr.optString(it) }
        }

        fun render(context: Context, mgr: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_question_of_day)
            val prefs = StudyWidgetSync.prefs(context)
            val queue = readQueue(context)

            views.setTextViewText(
                R.id.qotd_sync_time,
                prefs.getString("flutter.study_widget_sync_time", null) ?: ""
            )

            if (queue.isEmpty()) {
                views.setTextViewText(
                    R.id.qotd_question,
                    prefs.getString("flutter.study_qotd_question", null)
                        ?: "অ্যাপ খুললে আজকের প্রশ্ন আসবে"
                )
                for (id in OPTION_IDS) views.setTextViewText(id, "")
                views.setTextViewText(R.id.qotd_answer, "")
                finish(context, views, mgr, appWidgetId)
                return
            }

            val cursor = StudyWidgetSync.int(context, KEY_CURSOR, 0)
                .coerceIn(0, queue.size - 1)
            val entry = queue[cursor]
            val options = optionsOf(entry)
            val correct = entry.optInt("c", -1)
            val picked = StudyWidgetSync.int(context, KEY_PICKED, -1)
            val revealed = prefs.getBoolean(KEY_REVEALED, false)
            val answered = picked in options.indices
            val shown = answered || revealed

            views.setTextViewText(R.id.qotd_question, entry.optString("q"))

            for ((i, viewId) in OPTION_IDS.withIndex()) {
                if (i >= options.size) {
                    views.setTextViewText(viewId, "")
                    views.setInt(viewId, "setBackgroundResource", 0)
                    views.setOnClickPendingIntent(viewId, null)
                    continue
                }

                val marker = MARKERS.getOrElse(i) { "•" }
                views.setTextViewText(viewId, "$marker) ${options[i]}")

                // Once the answer is out, the right one is marked whether or
                // not it was the one chosen — being shown the right answer is
                // the point, not being told only that you were wrong.
                val background = when {
                    shown && i == correct -> R.drawable.widget_option_right
                    answered && i == picked -> R.drawable.widget_option_wrong
                    else -> R.drawable.widget_option_idle
                }
                views.setInt(viewId, "setBackgroundResource", background)

                views.setOnClickPendingIntent(
                    viewId,
                    WidgetIntents.broadcastWithExtra(
                        context,
                        QuestionOfDayWidgetProvider::class.java,
                        ACTION_ANSWER,
                        EXTRA_OPTION,
                        i,
                        requestCode = 40 + i
                    )
                )
            }

            val verdict = when {
                answered && picked == correct -> "✓ ঠিক হয়েছে"
                answered -> "✗ ঠিক উত্তর: ${MARKERS.getOrElse(correct) { "" }}"
                revealed -> "উত্তর: ${MARKERS.getOrElse(correct) { "" }}"
                else -> "উত্তর দেখুন"
            }
            views.setTextViewText(R.id.qotd_answer, verdict)
            views.setInt(
                R.id.qotd_answer,
                "setBackgroundResource",
                if (answered && picked == correct) {
                    R.drawable.widget_answer_revealed
                } else {
                    R.drawable.widget_reveal_button
                }
            )

            views.setOnClickPendingIntent(
                R.id.qotd_answer,
                WidgetIntents.broadcast(
                    context,
                    QuestionOfDayWidgetProvider::class.java,
                    ACTION_REVEAL,
                    requestCode = 30
                )
            )
            views.setOnClickPendingIntent(
                R.id.qotd_next,
                WidgetIntents.broadcast(
                    context,
                    QuestionOfDayWidgetProvider::class.java,
                    ACTION_NEXT,
                    requestCode = 33
                )
            )

            finish(context, views, mgr, appWidgetId)
        }

        /** The bits every render ends with. */
        private fun finish(
            context: Context,
            views: RemoteViews,
            mgr: AppWidgetManager,
            appWidgetId: Int
        ) {
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
