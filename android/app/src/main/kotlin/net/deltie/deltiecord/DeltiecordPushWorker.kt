package net.deltie.deltiecord

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.TimeUnit

/** Active UI engine, reused so Matrix never opens its crypto store twice. */
object DeltiecordEngineRegistry {
    @Volatile
    var engine: FlutterEngine? = null

    @Volatile
    var pushBridgeReady: Boolean = false

    @Volatile
    var appInForeground: Boolean = false
}

/**
 * Runs a bounded headless Matrix sync after a privacy-preserving UnifiedPush
 * hint. WorkManager is used because a broadcast receiver cannot safely keep a
 * Flutter engine/network request alive after onReceive returns.
 */
class DeltiecordPushWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun getForegroundInfo(): ForegroundInfo = ForegroundInfo(
        9002,
        DeltiecordNotificationPublisher.backgroundWorkNotification(applicationContext),
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else {
            0
        },
    )

    override suspend fun doWork(): Result {
        if (inputData.getString(KEY_JOB_KIND) == JOB_RECONCILE_PUSHER) {
            return reconcilePusher()
        }
        val roomId = inputData.getString(KEY_ROOM_ID)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        val eventId = inputData.getString(KEY_EVENT_ID)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        val notificationAction = inputData.getString(KEY_ACTION)
        // The live Dart session emits its own in-app banner. Posting an Android
        // notification as well duplicates the alert and can mark a visible
        // conversation as externally notified.
        if (notificationAction == null && DeltiecordEngineRegistry.appInForeground) {
            DeltiecordPushService.recordWorkerResult(
                applicationContext,
                "suppressed_phone_foreground",
            )
            DeltiecordPushWakeService.stop(applicationContext)
            return Result.success()
        }
        var ownsEngine = false
        var engine = DeltiecordEngineRegistry.engine
        try {
            if (engine != null) {
                withTimeout(15_000) {
                    while (!DeltiecordEngineRegistry.pushBridgeReady) delay(100)
                }
            } else {
                ownsEngine = true
                engine = startHeadlessEngine()
            }
            if (notificationAction != null) {
                val completed = invokeAction(
                    engine,
                    roomId,
                    eventId,
                    notificationAction,
                    inputData.getString(KEY_REPLY),
                )
                return if (completed || runAttemptCount >= 1) {
                    DeltiecordPushService.recordWorkerResult(
                        applicationContext,
                        if (completed) "action_completed" else "action_failed",
                    )
                    Result.success()
                } else {
                    Result.retry()
                }
            } else {
                val resolution = invokeResolver(engine, roomId, eventId)
                val resolutionStatus = resolution?.get("resolutionStatus") as? String
                if (resolutionStatus == "suppressed_active_desktop") {
                    DeltiecordPushService.recordWorkerResult(
                        applicationContext,
                        resolutionStatus,
                    )
                    return Result.success()
                }
                if (resolutionStatus != null) {
                    DeltiecordPushService.recordWorkerResult(
                        applicationContext,
                        "${resolutionStatus}_attempt_${runAttemptCount + 1}",
                    )
                    return if (runAttemptCount < MAX_RETRIES) {
                        Result.retry()
                    } else {
                        Result.success()
                    }
                }
                val message = resolution?.let(DeltiecordNotificationPublisher::fromMap)
                if (message != null) {
                    DeltiecordNotificationPublisher.publish(applicationContext, message)
                    DeltiecordPushService.recordWorkerResult(
                        applicationContext,
                        "notification_posted",
                    )
                } else {
                    DeltiecordPushService.recordWorkerResult(
                        applicationContext,
                        "event_not_resolved_attempt_${runAttemptCount + 1}",
                    )
                    return if (runAttemptCount < MAX_RETRIES) {
                        Result.retry()
                    } else {
                        Result.success()
                    }
                }
            }
            return Result.success()
        } catch (_: Throwable) {
            DeltiecordPushService.recordWorkerResult(
                applicationContext,
                "worker_failed_attempt_${runAttemptCount + 1}",
            )
            return if (runAttemptCount < MAX_RETRIES) {
                Result.retry()
            } else {
                Result.success()
            }
        } finally {
            DeltiecordNotificationPublisher.cancelBackgroundWorkNotification(
                applicationContext,
            )
            DeltiecordPushWakeService.stop(applicationContext)
            if (ownsEngine && engine != null) {
                withContext(Dispatchers.Main) { engine.destroy() }
            }
        }
    }

    private suspend fun reconcilePusher(): Result {
        val instance = inputData.getString(KEY_INSTANCE)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        // Endpoint registration and Matrix pusher verification are separate.
        // Re-registering on every app resume can rotate the private capability
        // while Matrix still points at the old endpoint. onNewEndpoint owns
        // registration; this path only verifies or repairs the Matrix pusher.
        val endpoint = DeltiecordPushService.endpoint(applicationContext, instance)
        if (endpoint == null) {
            DeltiecordPushService.recordRegistrationStage(
                applicationContext,
                "endpoint_missing",
            )
            DeltiecordPushService.recordPusherVerification(
                applicationContext,
                "endpoint_missing",
            )
            return Result.success()
        }
        var ownsEngine = false
        var engine = DeltiecordEngineRegistry.engine
        try {
            DeltiecordPushService.recordRegistrationStage(
                applicationContext,
                "pusher_verification_running",
            )
            if (engine != null) {
                withTimeout(15_000) {
                    while (!DeltiecordEngineRegistry.pushBridgeReady) delay(100)
                }
            } else {
                ownsEngine = true
                engine = startHeadlessEngine()
            }
            val result = invokePusherReconciliation(engine, endpoint)
            if (result == "verified" || result == "repaired") {
                DeltiecordPushService.recordRegistrationStage(
                    applicationContext,
                    "pusher_$result",
                )
                DeltiecordPushService.recordPusherVerification(
                    applicationContext,
                    result,
                )
                return Result.success()
            }
            DeltiecordPushService.recordPusherVerification(
                applicationContext,
                result ?: "verification_failed",
            )
            return if (runAttemptCount < MAX_RETRIES) Result.retry() else Result.success()
        } catch (_: Throwable) {
            DeltiecordPushService.recordRegistrationStage(
                applicationContext,
                "pusher_verification_failed",
            )
            DeltiecordPushService.recordPusherVerification(
                applicationContext,
                "verification_failed_attempt_${runAttemptCount + 1}",
            )
            return if (runAttemptCount < MAX_RETRIES) Result.retry() else Result.success()
        } finally {
            if (ownsEngine && engine != null) {
                withContext(Dispatchers.Main) { engine.destroy() }
            }
        }
    }

    private suspend fun startHeadlessEngine(): FlutterEngine = withContext(Dispatchers.Main) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val engine = FlutterEngine(applicationContext)
        val ready = CompletableDeferred<Unit>()
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                if (!ready.isCompleted) ready.complete(Unit)
                result.success(null)
            } else if (call.method == "getInitialTarget") {
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "deltiecordPushBackgroundMain",
            ),
        )
        withTimeout(20_000) { ready.await() }
        engine
    }

    private suspend fun invokeResolver(
        engine: FlutterEngine,
        roomId: String,
        eventId: String,
    ): Map<*, *>? = withContext(Dispatchers.Main) {
        val completed = CompletableDeferred<Map<*, *>?>()
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod(
            "resolveNotification",
            mapOf("roomId" to roomId, "eventId" to eventId),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    completed.complete(result as? Map<*, *>)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    completed.complete(null)
                }

                override fun notImplemented() {
                    completed.complete(null)
                }
            },
        )
        withTimeout(45_000) { completed.await() }
    }

    private suspend fun invokeAction(
        engine: FlutterEngine,
        roomId: String,
        eventId: String,
        action: String,
        reply: String?,
    ): Boolean = withContext(Dispatchers.Main) {
        val completed = CompletableDeferred<Boolean>()
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod(
            "performNotificationAction",
            mapOf(
                "roomId" to roomId,
                "eventId" to eventId,
                "action" to action,
                "reply" to reply,
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    completed.complete(result == true)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    completed.complete(false)
                }

                override fun notImplemented() {
                    completed.complete(false)
                }
            },
        )
        withTimeout(45_000) { completed.await() }
    }

    private suspend fun invokePusherReconciliation(
        engine: FlutterEngine,
        endpoint: String,
    ): String? = withContext(Dispatchers.Main) {
        val completed = CompletableDeferred<String?>()
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).invokeMethod(
            "reconcilePusher",
            mapOf("endpoint" to endpoint),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    completed.complete(result as? String)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    completed.complete(null)
                }

                override fun notImplemented() {
                    completed.complete(null)
                }
            },
        )
        withTimeout(45_000) { completed.await() }
    }

    companion object {
        private const val CHANNEL = "net.deltie.deltiecord/background_push"
        private const val KEY_ROOM_ID = "room_id"
        private const val KEY_EVENT_ID = "event_id"
        private const val KEY_ACTION = "notification_action"
        private const val KEY_REPLY = "notification_reply"
        private const val KEY_JOB_KIND = "job_kind"
        private const val KEY_INSTANCE = "instance"
        private const val JOB_RECONCILE_PUSHER = "reconcile_pusher"
        private const val MAX_RETRIES = 3

        private fun request(data: Data) =
            OneTimeWorkRequestBuilder<DeltiecordPushWorker>()
                .setInputData(data)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()

        private fun pusherRequest(data: Data) =
            OneTimeWorkRequestBuilder<DeltiecordPushWorker>()
                .setInputData(data)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
                .build()

        fun enqueue(context: Context, roomId: String, eventId: String) {
            val data = Data.Builder()
                .putString(KEY_ROOM_ID, roomId)
                .putString(KEY_EVENT_ID, eventId)
                .build()
            val request = request(data)
            WorkManager.getInstance(context).enqueueUniqueWork(
                "deltiecord-push-${roomId.hashCode()}",
                // Only the most recent event per room needs resolution. A
                // stalled encrypted-event lookup must not block later pushes.
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }

        fun enqueueAction(
            context: Context,
            roomId: String,
            eventId: String,
            action: String,
            reply: String?,
        ) {
            val data = Data.Builder()
                .putString(KEY_ROOM_ID, roomId)
                .putString(KEY_EVENT_ID, eventId)
                .putString(KEY_ACTION, action)
                .putString(KEY_REPLY, reply)
                .build()
            val request = request(data)
            WorkManager.getInstance(context).enqueueUniqueWork(
                "deltiecord-action-${roomId.hashCode()}",
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            )
        }

        fun enqueuePusherReconciliation(context: Context, instance: String) {
            if (instance.isBlank()) return
            val data = Data.Builder()
                .putString(KEY_JOB_KIND, JOB_RECONCILE_PUSHER)
                .putString(KEY_INSTANCE, instance)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "deltiecord-pusher-check-${instance.hashCode()}",
                ExistingWorkPolicy.REPLACE,
                pusherRequest(data),
            )
        }

        fun schedulePusherVerification(context: Context, instance: String) {
            if (instance.isBlank()) return
            val data = Data.Builder()
                .putString(KEY_JOB_KIND, JOB_RECONCILE_PUSHER)
                .putString(KEY_INSTANCE, instance)
                .build()
            val request = PeriodicWorkRequestBuilder<DeltiecordPushWorker>(
                12,
                TimeUnit.HOURS,
            )
                .setInputData(data)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "deltiecord-pusher-periodic-${instance.hashCode()}",
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }

        fun cancelPusherVerification(context: Context, instance: String) {
            val manager = WorkManager.getInstance(context)
            manager.cancelUniqueWork("deltiecord-pusher-check-${instance.hashCode()}")
            manager.cancelUniqueWork("deltiecord-pusher-periodic-${instance.hashCode()}")
        }
    }
}
