package net.deltie.deltiecord

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.UnifiedPush

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "net.deltie.deltiecord/unified_push"
        private const val NOTIFICATION_ASSETS_CHANNEL =
            "net.deltie.deltiecord/notification_assets"
        private const val REGISTRATION_TIMEOUT_MS = 30_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingRegistrations = mutableMapOf<String, MethodChannel.Result>()
    private var unifiedPushChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        unifiedPushChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    val instance = call.argument<String>("instance") ?: "default"
                    when (call.method) {
                        "getDistributors" -> result.success(UnifiedPush.getDistributors(this))
                        "getState" -> result.success(DeltiecordPushService.state(this, instance))
                        "selectDistributor" -> {
                            val distributor = call.argument<String>("distributor")
                            if (distributor.isNullOrBlank()) {
                                result.error("invalid_distributor", "Choose a UnifiedPush distributor.", null)
                            } else {
                                UnifiedPush.saveDistributor(this, distributor)
                                // An endpoint belongs to the selected distributor.
                                // Never reuse a stale capability after switching.
                                DeltiecordPushService.clear(this, instance)
                                registerUnifiedPush(instance, result)
                            }
                        }
                        "register" -> {
                            if (UnifiedPush.getSavedDistributor(this) == null) {
                                result.error("no_distributor", "No UnifiedPush distributor is selected.", null)
                            } else {
                                registerUnifiedPush(instance, result)
                            }
                        }
                        "unregister" -> {
                            UnifiedPush.unregister(this, instance)
                            DeltiecordPushService.clear(this, instance)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        DeltiecordPushService.stateChangedListener = { instance ->
            mainHandler.post { completeUnifiedPushRegistration(instance) }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_ASSETS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "cacheRoomAvatar" -> {
                    val roomId = call.argument<String>("roomId")
                    val avatar = call.argument<ByteArray>("avatar")
                    if (roomId.isNullOrBlank() || avatar == null) {
                        result.error("invalid_avatar", "Missing room avatar data.", null)
                    } else {
                        result.success(NotificationAvatarCache.put(this, roomId, avatar))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerUnifiedPush(instance: String, result: MethodChannel.Result) {
        pendingRegistrations.remove(instance)?.error(
            "registration_replaced",
            "A newer UnifiedPush registration replaced this request.",
            null,
        )
        pendingRegistrations[instance] = result
        try {
            UnifiedPush.register(
                this,
                instance,
                // Element X labels registrations by session so multi-account
                // distributor UIs remain understandable.
                messageForDistributor = instance.take(100),
            )
        } catch (exception: Exception) {
            pendingRegistrations.remove(instance)
            result.error("registration_failed", exception.message, null)
            return
        }
        mainHandler.postDelayed(
            {
                pendingRegistrations.remove(instance)?.error(
                    "registration_timeout",
                    "The UnifiedPush distributor did not return an endpoint within 30 seconds.",
                    null,
                )
            },
            REGISTRATION_TIMEOUT_MS,
        )
    }

    private fun completeUnifiedPushRegistration(instance: String) {
        val state = DeltiecordPushService.state(this, instance)
        pendingRegistrations.remove(instance)?.let { result ->
            val endpoint = state["endpoint"]
            val error = state["error"]
            if (!endpoint.isNullOrBlank()) {
                result.success(state)
            } else if (!error.isNullOrBlank()) {
                result.error("registration_failed", error, null)
            }
        }
        // This callback also handles endpoint rotation that was initiated by
        // the distributor rather than by an explicit Settings action.
        unifiedPushChannel?.invokeMethod(
            "onStateChanged",
            mapOf("instance" to instance),
        )
    }

    override fun onDestroy() {
        if (DeltiecordPushService.stateChangedListener != null) {
            DeltiecordPushService.stateChangedListener = null
        }
        pendingRegistrations.values.forEach {
            it.error("activity_destroyed", "UnifiedPush registration was interrupted.", null)
        }
        pendingRegistrations.clear()
        unifiedPushChannel = null
        super.onDestroy()
    }
}
