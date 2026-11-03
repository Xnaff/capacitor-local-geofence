package de.xnaff.capacitor.localgeofence

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.getcapacitor.Logger
import com.google.android.gms.tasks.Tasks
import java.util.concurrent.TimeUnit

/** Re-adds stored regions in the background and retries transient failures with backoff. */
class GeofenceRestoreWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val tasks = GeofenceRegistrar.restoreAll(applicationContext)
        return try {
            Tasks.await(Tasks.whenAllSuccess<Void>(tasks), 60, TimeUnit.SECONDS)
            Result.success()
        } catch (error: Exception) {
            Logger.error("LocalGeofence", "Restore attempt ${runAttemptCount + 1} failed", error)
            if (runAttemptCount + 1 < MAX_ATTEMPTS) Result.retry() else Result.failure()
        }
    }

    companion object {
        private const val WORK_NAME = "de.xnaff.capacitor.localgeofence.restore"
        private const val MAX_ATTEMPTS = 5

        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<GeofenceRestoreWorker>()
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
        }
    }
}
