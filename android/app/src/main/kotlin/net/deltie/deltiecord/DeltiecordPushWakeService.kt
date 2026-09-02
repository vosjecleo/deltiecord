package net.deltie.deltiecord

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import androidx.core.content.ContextCompat

/** Keeps Android awake while the UnifiedPush broadcast is handed to WorkManager. */
class DeltiecordPushWakeService : Service() {
    private val handler by lazy { Handler(mainLooper) }
    private val safetyStop = Runnable { stopSelf() }

    override fun onCreate() {
        super.onCreate()
        startForeground(
            NOTIFICATION_ID,
            DeltiecordNotificationPublisher.backgroundWorkNotification(this),
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.removeCallbacks(safetyStop)
        handler.postDelayed(safetyStop, MAX_LIFETIME_MS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(safetyStop)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val NOTIFICATION_ID = 9002
        private const val MAX_LIFETIME_MS = 90_000L

        fun start(context: Context) {
            runCatching {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, DeltiecordPushWakeService::class.java),
                )
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DeltiecordPushWakeService::class.java))
        }
    }
}
