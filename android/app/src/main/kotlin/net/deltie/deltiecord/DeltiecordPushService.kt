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
import org.json.JSONObject

/**
 * Receives capability endpoints and Matrix sync pokes from a user-selected
 * UnifiedPush distributor. Endpoint URLs stay in private Android preferences;
 * they are never logged because they are bearer capabilities.
 */
class DeltiecordPushService : PushService() {
    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) {
        val endpointUrl = endpoint.url
            .replace(Regex("[\\u0000-\\u001f\\u007f\\u200b\\ufeff]"), "")
            .trim()
        if (endpointUrl.isBlank()) {
            preferences(this).edit()
                .putString(errorKey(instance), "EMPTY_ENDPOINT")
                .apply()
            stateChangedListener?.invoke(instance)
            return
        }
        preferences(this).edit()
            .putString(endpointKey(instance), endpointUrl)
            .remove(errorKey(instance))
            .apply()
        stateChangedListener?.invoke(instance)
    }

    override fun onMessage(message: PushMessage, instance: String) {
        // Matrix push payloads are wake-up hints, not a source of decrypted
        // message text. Deltiecord syncs Matrix after the user opens the alert.
        showMatrixActivityNotification(this, message.content)
    }

    override fun onRegistrationFailed(reason: FailedReason, instance: String) {
        preferences(this).edit()
            .putString(errorKey(instance), reason.name)
            .apply()
        stateChangedListener?.invoke(instance)
    }

    override fun onUnregistered(instance: String) {
        clear(this, instance)
        stateChangedListener?.invoke(instance)
    }

    companion object {
        private const val PREFS = "deltiecord_unified_push"
        private const val CHANNEL_ID = "matrix_activity"

        /**
         * Completes an in-flight registration while Flutter is alive.
         *
         * UnifiedPush registration is asynchronous: `register()` merely asks
         * the distributor to create or refresh an endpoint. Element X uses the
         * same callback-correlated lifecycle and waits for `onNewEndpoint`
         * before it registers the Matrix pusher. When Flutter is not alive the
         * endpoint remains in private preferences and is reconciled on launch.
         */
        @Volatile
        var stateChangedListener: ((String) -> Unit)? = null

        private fun preferences(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun endpointKey(instance: String) = "endpoint:$instance"
        private fun errorKey(instance: String) = "error:$instance"

        fun state(context: Context, instance: String): Map<String, String?> = mapOf(
            "distributor" to org.unifiedpush.android.connector.UnifiedPush.getSavedDistributor(context),
            "endpoint" to preferences(context).getString(endpointKey(instance), null),
            "error" to preferences(context).getString(errorKey(instance), null),
        )

        fun clear(context: Context, instance: String) {
            preferences(context).edit()
                .remove(endpointKey(instance))
                .remove(errorKey(instance))
                .apply()
        }

        private fun showMatrixActivityNotification(context: Context, payload: ByteArray) {
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
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(context)
            }
            val metadata = parseMatrixMetadata(payload)
            val avatar = NotificationAvatarCache.get(context, metadata.roomId)
            builder
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(metadata.title)
                .setContentText("New Matrix activity")
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .apply { if (avatar != null) setLargeIcon(avatar) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && avatar != null) {
                val sender = android.app.Person.Builder()
                    .setName(metadata.title)
                    .setIcon(android.graphics.drawable.Icon.createWithBitmap(avatar))
                    .build()
                builder.setStyle(
                    android.app.Notification.MessagingStyle(sender)
                        .addMessage("New Matrix activity", System.currentTimeMillis(), sender),
                )
            }
            val notification = builder.build()
            manager.notify(9001, notification)
        }

        private data class MatrixMetadata(val roomId: String?, val title: String)

        private fun parseMatrixMetadata(payload: ByteArray): MatrixMetadata = runCatching {
            if (payload.size > 256 * 1024) return@runCatching MatrixMetadata(null, "Deltiecord")
            val json = JSONObject(payload.toString(Charsets.UTF_8))
            val roomId = json.optString("room_id").takeIf { it.isNotBlank() }
            val title = json.optString("room_name").takeIf { it.isNotBlank() }
                ?: json.optString("sender_display_name").takeIf { it.isNotBlank() }
                ?: "Deltiecord"
            MatrixMetadata(roomId, title.take(128))
        }.getOrDefault(MatrixMetadata(null, "Deltiecord"))
    }
}
