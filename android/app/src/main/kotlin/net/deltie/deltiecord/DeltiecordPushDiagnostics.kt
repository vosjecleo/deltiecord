package net.deltie.deltiecord

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.UUID

/** Performs a secret-safe round trip through the configured Matrix push gateway. */
object DeltiecordPushDiagnostics {
    fun run(
        context: Context,
        instance: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        val endpoint = DeltiecordPushService.endpoint(context, instance)
        if (endpoint == null) {
            callback(Result.failure(IllegalStateException("No UnifiedPush endpoint is registered.")))
            return
        }
        Thread {
            val result = runCatching {
                val endpointUri = URI(endpoint)
                require(endpointUri.scheme.equals("https", ignoreCase = true)) {
                    "The UnifiedPush endpoint is not HTTPS."
                }
                val gateway = URI(
                    endpointUri.scheme,
                    endpointUri.authority,
                    "/_matrix/push/v1/notify",
                    null,
                    null,
                ).toString()
                val testEventId = DeltiecordPushService.TEST_EVENT_PREFIX + UUID.randomUUID()
                val startedAt = System.currentTimeMillis()
                DeltiecordPushService.recordTestRequest(context, "gateway_requesting")
                val device = JSONObject()
                    .put("app_id", "net.deltie.deltiecord")
                    .put("pushkey", endpoint)
                    .put("pushkey_ts", startedAt)
                    .put(
                        "data",
                        JSONObject()
                            .put("url", gateway)
                            .put("format", "event_id_only"),
                    )
                    .put("tweaks", JSONObject())
                val notification = JSONObject()
                    .put("event_id", testEventId)
                    .put("room_id", "!deltiecord-push-diagnostic:localhost")
                    .put("type", "m.room.message")
                    .put("sender", "@deltiecord-push-test:localhost")
                    .put("sender_display_name", "Deltiecord diagnostics")
                    .put("room_name", "Push diagnostics")
                    .put("devices", JSONArray().put(device))
                val body = JSONObject().put("notification", notification)
                    .toString()
                    .toByteArray(Charsets.UTF_8)
                val connection = URL(gateway).openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "POST"
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 10_000
                    connection.readTimeout = 10_000
                    connection.doOutput = true
                    connection.setFixedLengthStreamingMode(body.size)
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.outputStream.use { it.write(body) }
                    require(connection.responseCode in 200..299) {
                        "Matrix gateway returned HTTP ${connection.responseCode}."
                    }
                } finally {
                    connection.disconnect()
                }
                DeltiecordPushService.recordTestResult(context, "gateway_accepted")
                val deadline = System.currentTimeMillis() + 15_000
                while (System.currentTimeMillis() < deadline) {
                    if (DeltiecordPushService.lastTestReceived(context) >= startedAt) {
                        DeltiecordPushService.recordTestResult(context, "receiver_verified")
                        return@runCatching
                    }
                    Thread.sleep(150)
                }
                throw IllegalStateException(
                    "The gateway accepted the test, but Android did not receive it within 15 seconds.",
                )
            }.onFailure {
                DeltiecordPushService.recordTestResult(context, "failed")
            }
            callback(result)
        }.apply {
            name = "DeltiecordPushDiagnostics"
            isDaemon = true
            start()
        }
    }
}
