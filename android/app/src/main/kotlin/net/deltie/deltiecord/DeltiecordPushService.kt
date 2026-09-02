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
        val previous = preferences(context).getString(endpointKey(instance), null)
        val editor = preferences(context).edit()
            .putString(endpointKey(instance), endpointUrl)
            .putString("last_instance", instance)
            .putString("last_pusher_result", "verification_pending")
            .remove(errorKey(instance))
        if (previous != endpointUrl) {
            editor.putLong("last_endpoint_rotation_ms", System.currentTimeMillis())
        }
        editor.apply()
        if (previous != endpointUrl) {
            DeltiecordPushWorker.enqueuePusherReconciliation(context, instance)
        }
        DeltiecordPushWorker.schedulePusherVerification(context, instance)
        stateChangedListener?.invoke(instance)
    }

    override fun onMessage(context: Context, message: PushMessage, instance: String) {
        // Matrix push payloads are wake-up hints, not a source of decrypted
        // message text. Do not post an intermediate generic notification: if
        // local decryption is slow or fails that placeholder otherwise becomes
        // a permanent, content-free "silent" alert.
        preferences(context).edit()
            .putLong("last_message_received_ms", System.currentTimeMillis())
            .apply()
        val metadata = parseMatrixMetadata(message.content)
        if (metadata.roomId != null && metadata.eventId != null) {
            DeltiecordPushWorker.enqueue(context, metadata.roomId, metadata.eventId)
        }
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
            "lastWorkerResult" to preferences(context)
                .getString("last_worker_result", null),
            "lastEndpointRotation" to preferences(context)
                .getLong("last_endpoint_rotation_ms", 0L)
                .takeIf { it > 0L }
                ?.toString(),
            "lastPusherVerification" to preferences(context)
                .getLong("last_pusher_verification_ms", 0L)
                .takeIf { it > 0L }
                ?.toString(),
            "lastPusherResult" to preferences(context)
                .getString("last_pusher_result", null),
        )

        fun recordWorkerResult(context: Context, result: String) {
            preferences(context).edit()
                .putString("last_worker_result", result.take(96))
                .apply()
        }

        fun recordPusherVerification(context: Context, result: String) {
            preferences(context).edit()
                .putLong("last_pusher_verification_ms", System.currentTimeMillis())
                .putString("last_pusher_result", result.take(96))
                .apply()
        }

        fun rememberInstance(context: Context, instance: String) {
            preferences(context).edit().putString("last_instance", instance).apply()
        }

        fun knownInstance(context: Context): String? = preferences(context)
            .getString("last_instance", null)
            ?.takeIf { it.isNotBlank() }

        fun endpoint(context: Context, instance: String): String? = preferences(context)
            .getString(endpointKey(instance), null)
            ?.takeIf { it.isNotBlank() }

        fun clear(context: Context, instance: String) {
            val editor = preferences(context).edit()
                .remove(endpointKey(instance))
                .remove(errorKey(instance))
            if (knownInstance(context) == instance) editor.remove("last_instance")
            editor.apply()
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
