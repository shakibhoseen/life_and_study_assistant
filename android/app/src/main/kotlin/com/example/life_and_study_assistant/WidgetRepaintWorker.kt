package com.example.life_and_study_assistant

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Repaints every widget from whatever is in preferences.
 *
 * A refresh tapped while the app is closed goes to a Dart background isolate,
 * which writes the new figures and then asks the native side to repaint over a
 * MethodChannel. There is no MethodChannel in a background isolate — it
 * belongs to MainActivity — so that last step silently does nothing, and the
 * office widget sat on "Syncing... ⏳" for good.
 *
 * This runs a little after the sync is queued and paints whatever is there by
 * then. Worst case it paints the old figures, which is the honest outcome: a
 * refresh that could not fetch should look finished and stale, not eternally
 * busy.
 */
class WidgetRepaintWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    override fun doWork(): Result {
        return try {
            OfficeStatusWidgetProvider.updateAllWidgets(applicationContext)
            StudyWidgetSync.updateAll(applicationContext)
            Result.success()
        } catch (_: Throwable) {
            // Nothing here is worth a retry: the next tap, or the next time
            // the app runs, repaints anyway.
            Result.success()
        }
    }
}
