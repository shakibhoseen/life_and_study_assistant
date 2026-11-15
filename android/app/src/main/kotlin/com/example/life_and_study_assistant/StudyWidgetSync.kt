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

            WorkManager.getInstance(context).enqueueUniqueWork(
                "study_widget_refresh_task",
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                    .setInputData(data)
                    .build()
            )
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Repaints every study widget on the home screen. */
    fun updateAll(context: Context) {
        StudyTodayWidgetProvider.refreshAll(context)
        ExamCountdownWidgetProvider.refreshAll(context)
        QuestionOfDayWidgetProvider.refreshAll(context)
    }
}
