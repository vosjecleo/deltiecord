package net.deltie.deltiecord

import android.content.Context
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.MessagingReceiver
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage
import org.json.JSONObject

/**
 * Receives capability endpoints and Matrix sync pokes from a user-selected
 * UnifiedPush distributor. Endpoint URLs stay in private Android preferences;
 * they are never logged because they are bearer capabilities.
 */
class DeltiecordPushService : MessagingReceiver() {
    override fun onNewEndpoint(context: Context, endpoint: PushEndpoint, instance: String) {
        val endpointUrl = endpoint.url
            .replace(Regex("[\\u0000-\\u001f\\u007f\\u200b\\ufeff]"), "")
            .trim()
        if (endpointUrl.isBlank()) {
            preferences(context).edit()
                .putString(errorKey(instance), "EMPTY_ENDPOINT")
                .apply()
            stateChangedListener?.invoke(instance)
            return
        }
        preferences(context).edit()
            .putString(endpointKey(instance), endpointUrl)
            .remove(errorKey(instance))
            .apply()
        stateChangedListener?.invoke(instance)
    }

    override fun onMessage(context: Context, message: PushMessage, instance: String) {
        // Matrix push payloads are wake-up hints, not a source of decrypted
        // message text. Deltiecord syncs Matrix after the user opens the alert.
        preferences(context).edit()
            .putLong("last_message_received_ms", System.currentTimeMillis())
            .apply()
        val metadata = parseMatrixMetadata(message.content)
        DeltiecordNotificationPublisher.showPlaceholder(
            context,
            metadata.roomId,
            metadata.eventId,
            metadata.title,
        )
        if (metadata.roomId != null && metadata.eventId != null) {
            DeltiecordPushWorker.enqueue(context, metadata.roomId, metadata.eventId)
        }
        preferences(context).edit()
            .putLong("last_notification_posted_ms", System.currentTimeMillis())
            .apply()
    }

    override fun onRegistrationFailed(context: Context, reason: FailedReason, instance: String) {
        preferences(context).edit()
            .putString(errorKey(instance), reason.name)
            .apply()
        stateChangedListener?.invoke(instance)
    }

    override fun onUnregistered(context: Context, instance: String) {
        clear(context, instance)
        stateChangedListener?.invoke(instance)
    }

    companion object {
        private const val PREFS = "deltiecord_unified_push"

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
            "lastMessageReceived" to preferences(context)
                .getLong("last_message_received_ms", 0L)
                .takeIf { it > 0L }
                ?.toString(),
            "lastNotificationPosted" to preferences(context)
                .getLong("last_notification_posted_ms", 0L)
                .takeIf { it > 0L }
                ?.toString(),
        )

        fun clear(context: Context, instance: String) {
            preferences(context).edit()
                .remove(endpointKey(instance))
                .remove(errorKey(instance))
                .apply()
        }

        fun clearError(context: Context, instance: String) {
            preferences(context).edit()
                .remove(errorKey(instance))
                .apply()
        }

        private data class MatrixMetadata(
            val roomId: String?,
            val eventId: String?,
            val title: String,
        )

        private fun parseMatrixMetadata(payload: ByteArray): MatrixMetadata = runCatching {
            if (payload.size > 256 * 1024) {
                return@runCatching MatrixMetadata(null, null, "Deltiecord")
            }
            val root = JSONObject(payload.toString(Charsets.UTF_8))
            val json = root.optJSONObject("notification") ?: root
            val roomId = json.optString("room_id").takeIf { it.isNotBlank() }
            val eventId = json.optString("event_id").takeIf { it.isNotBlank() }
            val roomName = json.optString("room_name").takeIf { it.isNotBlank() }
            val senderName = json.optString("sender_display_name").takeIf { it.isNotBlank() }
            val title = when {
                senderName != null && roomName != null && senderName != roomName ->
                    "$senderName in $roomName"
                senderName != null -> senderName
                roomName != null -> roomName
                else -> "Deltiecord"
            }
            MatrixMetadata(roomId, eventId, title.take(128))
        }.getOrDefault(MatrixMetadata(null, null, "Deltiecord"))
    }
}
