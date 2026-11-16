package com.example.life_and_study_assistant

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker

/**
 * Asking Dart to recollect the study figures.
 *
 * The study widgets render SharedPreferences and nothing else: the numbers
 * come out of the drift database, which only Dart can open. So a refresh is a
 * request, not a calculation — the same two routes the office widget uses.
 */
object StudyWidgetSync {

    const val ACTION_REFRESH = "com.example.life_and_study_assistant.REFRESH_STUDY_WIDGET"
    const val ACTION_UPDATE_DATA = "com.example.life_and_study_assistant.UPDATE_STUDY_WIDGET_DATA"

    /** The Dart task name the background worker dispatches on. */
    private const val DART_TASK = "com.example.life_and_study_assistant.study_widget_sync"

    fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /**
     * Reads a number Flutter wrote.
     *
     * shared_preferences stores a Dart `int` as a Java **Long**, so getInt()
     * on one of these throws ClassCastException — and a throw inside a widget
     * provider kills the receiver, which is what puts "Tap to open this app so
     * your widget can refresh" on the home screen. Read it as a Long, and fall
     * back to Int for anything the native side wrote itself.
     */
    fun int(context: Context, key: String, fallback: Int): Int {
        val prefs = prefs(context)
        return try {
            prefs.getLong(key, fallback.toLong()).toInt()
        } catch (_: ClassCastException) {
            try {
                prefs.getInt(key, fallback)
            } catch (_: ClassCastException) {
                fallback
            }
        }
    }

    /**
     * Returns true if a live engine was asked, false if the work was queued or
     * could not be started at all — in which case the caller repaints what it
     * already has rather than leaving the widget looking stuck.
     */
    fun request(context: Context): Boolean {
        if (MainActivity.activeChannel != null) {
            MainActivity.requestStudyWidgetRefresh()
            return true
        }
        return try {
            val data = Data.Builder()
                .putString(BackgroundWorker.DART_TASK_KEY, DART_TASK)
                .putString(
                    "dev.fluttercommunity.workmanager.UNIQUE_NAME",
                    "study_widget_sync_${System.currentTimeMillis()}"
                )
                .build()

            // Chained, not timed: the repaint runs the moment the sync
            // worker finishes, however long that takes. A fixed delay was
            // guesswork — the first one was twenty seconds for a sync that
            // measured two, so most of the wait was the guess.
            WorkManager.getInstance(context)
                .beginUniqueWork(
                    "study_widget_refresh_task",
                    ExistingWorkPolicy.REPLACE,
                    OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                        .setInputData(data)
                        .build()
                )
                .then(repaintRequest())
                .enqueue()
            queueRepaintAfterSync(context)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** A repaint that runs as soon as whatever it is chained to finishes. */
    fun repaintRequest(): OneTimeWorkRequest =
        OneTimeWorkRequest.Builder(WidgetRepaintWorker::class.java).build()

    /**
     * A repaint far enough out to catch a sync that never reported back.
     *
     * The chain below handles the normal case. This is for when the sync
     * worker dies outright: a chained job does not run after a failed parent,
     * and a widget left saying "Syncing..." is the thing being prevented.
     */
    fun queueRepaintAfterSync(context: Context) {
        try {
            WorkManager.getInstance(context).enqueueUniqueWork(
                "widget_repaint_backstop",
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequest.Builder(WidgetRepaintWorker::class.java)
                    .setInitialDelay(45, java.util.concurrent.TimeUnit.SECONDS)
                    .build()
            )
        } catch (_: Throwable) {
            // Then the next tap or app launch repaints instead.
        }
    }

    /**
     * Repaints every study widget on the home screen.
     *
     * Each one is isolated. These run inside a broadcast receiver, where an
     * exception does not just skip a repaint — it kills the receiver and
     * Android marks the widget as needing the app opened. One widget failing
     * took all three down once already; it should cost only itself.
     */
    fun updateAll(context: Context) {
        for (refresh in listOf<(Context) -> Unit>(
            StudyTodayWidgetProvider::refreshAll,
            ExamCountdownWidgetProvider::refreshAll,
            QuestionOfDayWidgetProvider::refreshAll
        )) {
            try {
                refresh(context)
            } catch (e: Throwable) {
                android.util.Log.e("StudyWidget", "a widget failed to render", e)
            }
        }
    }
}
