package net.deltie.deltiecord

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
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
        val roomId = inputData.getString(KEY_ROOM_ID)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        val eventId = inputData.getString(KEY_EVENT_ID)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        // The live Dart session emits its own in-app banner. Posting an Android
        // notification as well duplicates the alert and can mark a visible
        // conversation as externally notified.
        if (DeltiecordEngineRegistry.appInForeground) return Result.success()
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
            val resolution = invokeResolver(engine, roomId, eventId)
            val message = resolution?.let(DeltiecordNotificationPublisher::fromMap)
            if (message != null) {
                DeltiecordNotificationPublisher.publish(applicationContext, message)
            }
            return Result.success()
        } catch (_: Throwable) {
            // The receiver's generic notification remains visible. Retry once
            // so transient sync/key-delivery races can still enrich it.
            return if (runAttemptCount < 1) Result.retry() else Result.success()
        } finally {
            DeltiecordNotificationPublisher.cancelBackgroundWorkNotification(
                applicationContext,
            )
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

    companion object {
        private const val CHANNEL = "net.deltie.deltiecord/background_push"
        private const val KEY_ROOM_ID = "room_id"
        private const val KEY_EVENT_ID = "event_id"

        fun enqueue(context: Context, roomId: String, eventId: String) {
            val data = Data.Builder()
                .putString(KEY_ROOM_ID, roomId)
                .putString(KEY_EVENT_ID, eventId)
                .build()
            val request = OneTimeWorkRequestBuilder<DeltiecordPushWorker>()
                .setInputData(data)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "deltiecord-push-${roomId.hashCode()}",
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            )
        }
    }
}
