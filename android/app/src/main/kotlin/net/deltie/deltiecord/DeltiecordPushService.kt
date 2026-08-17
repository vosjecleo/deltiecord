package net.deltie.deltiecord

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.PushService
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage

/**
 * Receives capability endpoints and Matrix sync pokes from a user-selected
 * UnifiedPush distributor. Endpoint URLs stay in private Android preferences;
 * they are never logged because they are bearer capabilities.
 */
class DeltiecordPushService : PushService() {
    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) {
        preferences(this).edit()
            .putString(endpointKey(instance), endpoint.url)
            .remove(errorKey(instance))
            .apply()
    }

    override fun onMessage(message: PushMessage, instance: String) {
        // Matrix push payloads are wake-up hints, not a source of decrypted
        // message text. Deltiecord syncs Matrix after the user opens the alert.
        showMatrixActivityNotification(this)
    }

    override fun onRegistrationFailed(reason: FailedReason, instance: String) {
        preferences(this).edit()
            .putString(errorKey(instance), reason.name)
            .apply()
    }

    override fun onUnregistered(instance: String) {
        clear(this, instance)
    }

    companion object {
        private const val PREFS = "deltiecord_unified_push"
        private const val CHANNEL_ID = "matrix_activity"

        private fun preferences(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun endpointKey(instance: String) = "endpoint:$instance"
        private fun errorKey(instance: String) = "error:$instance"

        fun state(context: Context, instance: String): Map<String, String?> = mapOf(
            "distributor" to org.unifiedpush.android.connector.UnifiedPush.getSavedDistributor(context),
            "endpoint" to preferences(context).getString(endpointKey(instance), null),
            "error" to preferences(context).getString(errorKey(instance), null),
        )

        fun clearError(context: Context, instance: String) {
            preferences(context).edit().remove(errorKey(instance)).apply()
        }

        fun clear(context: Context, instance: String) {
            preferences(context).edit()
                .remove(endpointKey(instance))
                .remove(errorKey(instance))
                .apply()
        }

        private fun showMatrixActivityNotification(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Matrix activity",
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                )
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(context)
            }
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Deltiecord")
                .setContentText("New Matrix activity")
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()
            manager.notify(9001, notification)
        }
    }
}
