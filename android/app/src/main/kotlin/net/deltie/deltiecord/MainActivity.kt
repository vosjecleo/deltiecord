package net.deltie.deltiecord

import android.os.Handler
import android.os.Looper
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.UnifiedPush

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "net.deltie.deltiecord/unified_push"
        private const val NOTIFICATION_ASSETS_CHANNEL =
            "net.deltie.deltiecord/notification_assets"
        private const val BACKGROUND_PUSH_CHANNEL =
            "net.deltie.deltiecord/background_push"
        private const val REGISTRATION_TIMEOUT_MS = 30_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingRegistrations = mutableMapOf<String, MethodChannel.Result>()
    private var unifiedPushChannel: MethodChannel? = null
    private var backgroundPushChannel: MethodChannel? = null
    private var configuredEngine: FlutterEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configuredEngine = flutterEngine
        DeltiecordEngineRegistry.engine = flutterEngine
        unifiedPushChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    val account = call.argument<String>("instance") ?: "default"
                    when (call.method) {
                        "getDistributors" -> result.success(
                            UnifiedPush.getDistributors(this).map { packageName ->
                                mapOf(
                                    "packageName" to packageName,
                                    "label" to distributorLabel(packageName),
                                )
                            },
                        )
                        "getState" -> {
                            val instance = DeltiecordPushService.instanceForAccount(
                                this,
                                account,
                                create = false,
                            )
                            result.success(DeltiecordPushService.state(this, instance))
                        }
                        "selectDistributor" -> {
                            val distributor = call.argument<String>("distributor")
                            if (distributor.isNullOrBlank()) {
                                result.error("invalid_distributor", "Choose a UnifiedPush distributor.", null)
                            } else {
                                val previous = DeltiecordPushService.instanceForAccount(
                                    this,
                                    account,
                                    create = false,
                                )
                                runCatching { UnifiedPush.unregister(this, previous) }
                                DeltiecordPushService.clear(this, previous)
                                DeltiecordPushService.forgetInstanceForAccount(
                                    this,
                                    account,
                                    previous,
                                )
                                UnifiedPush.saveDistributor(this, distributor)
                                // An endpoint belongs to the selected distributor.
                                // Never reuse a stale capability after switching.
                                registerUnifiedPush(account, result)
                            }
                        }
                        "register" -> {
                            if (UnifiedPush.getSavedDistributor(this) == null) {
                                result.error("no_distributor", "No UnifiedPush distributor is selected.", null)
                            } else {
                                registerUnifiedPush(account, result)
                            }
                        }
                        "unregister" -> {
                            // Removing the distributor as well as its instance
                            // prevents Refresh from silently reusing a rejected
                            // or uninstalled provider.
                            val instance = DeltiecordPushService.instanceForAccount(
                                this,
                                account,
                                create = false,
                            )
                            runCatching { UnifiedPush.unregister(this, instance) }
                            DeltiecordPushService.clear(this, instance)
                            DeltiecordPushWorker.cancelPusherVerification(this, instance)
                            DeltiecordPushService.forgetInstanceForAccount(
                                this,
                                account,
                                instance,
                            )
                            UnifiedPush.removeDistributor(this)
                            result.success(null)
                        }
                        "testPush" -> {
                            val instance = DeltiecordPushService.instanceForAccount(
                                this,
                                account,
                                create = false,
                            )
                            DeltiecordPushDiagnostics.run(this, instance) { testResult ->
                                mainHandler.post {
                                    testResult.fold(
                                        onSuccess = {
                                            result.success(
                                                DeltiecordPushService.state(this, instance),
                                            )
                                        },
                                        onFailure = { exception ->
                                            result.error(
                                                "push_test_failed",
                                                exception.message,
                                                null,
                                            )
                                        },
                                    )
                                }
                            }
                        }
                        "recordPusherVerification" -> {
                            val verification = call.argument<String>("result")
                                ?.takeIf { it.isNotBlank() }
                            if (verification == null) {
                                result.error("invalid_result", "Missing pusher result.", null)
                            } else {
                                DeltiecordPushService.recordPusherVerification(
                                    this,
                                    verification,
                                )
                                result.success(null)
                            }
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
                "showRichNotification" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val message = arguments?.let(DeltiecordNotificationPublisher::fromMap)
                    if (message == null) {
                        result.error("invalid_notification", "Missing notification data.", null)
                    } else {
                        DeltiecordNotificationPublisher.publish(this, message)
                        result.success(null)
                    }
                }
                "clearPrivateState" -> {
                    DeltiecordNotificationPublisher.clearPrivateState(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        backgroundPushChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_PUSH_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        DeltiecordEngineRegistry.pushBridgeReady = true
                        result.success(null)
                    }
                    "getInitialTarget" -> result.success(notificationTarget(intent, clear = true))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val target = notificationTarget(intent, clear = true) ?: return
        backgroundPushChannel?.invokeMethod("onNotificationActivated", target)
    }

    override fun onResume() {
        super.onResume()
        DeltiecordEngineRegistry.appInForeground = true
        DeltiecordPushService.knownInstance(this)?.let { instance ->
            DeltiecordPushWorker.enqueuePusherReconciliation(this, instance)
            DeltiecordPushWorker.schedulePusherVerification(this, instance)
        }
    }

    override fun onPause() {
        DeltiecordEngineRegistry.appInForeground = false
        super.onPause()
    }

    private fun notificationTarget(intent: Intent?, clear: Boolean): Map<String, String>? {
        val roomId = intent?.getStringExtra("notification_room_id")
        val eventId = intent?.getStringExtra("notification_event_id")
        if (roomId.isNullOrBlank() || eventId.isNullOrBlank()) return null
        if (clear) {
            intent.removeExtra("notification_room_id")
            intent.removeExtra("notification_event_id")
        }
        return mapOf("roomId" to roomId, "eventId" to eventId)
    }

    private fun registerUnifiedPush(account: String, result: MethodChannel.Result) {
        val instance = DeltiecordPushService.instanceForAccount(
            this,
            account,
            create = true,
        )
        DeltiecordPushService.rememberInstance(this, instance)
        DeltiecordPushWorker.schedulePusherVerification(this, instance)
        DeltiecordPushService.clearError(this, instance)
        pendingRegistrations.remove(instance)?.error(
            "registration_replaced",
            "A newer UnifiedPush registration replaced this request.",
            null,
        )
        pendingRegistrations[instance] = result
        DeltiecordPushService.recordRegistrationStage(this, "registration_requested")
        try {
            UnifiedPush.register(
                this,
                instance,
                // Keep the distributor label useful without exposing the
                // account identifier as the connector's routing key.
                messageForDistributor = account.take(100),
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

    private fun distributorLabel(packageName: String): String = try {
        val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
        packageManager.getApplicationLabel(applicationInfo).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        packageName
    }

    private fun completeUnifiedPushRegistration(instance: String) {
        val state = DeltiecordPushService.state(this, instance)
        val account = DeltiecordPushService.accountForInstance(this, instance)
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
            mapOf("instance" to account),
        )
    }

    override fun onDestroy() {
        DeltiecordEngineRegistry.appInForeground = false
        if (DeltiecordPushService.stateChangedListener != null) {
            DeltiecordPushService.stateChangedListener = null
        }
        pendingRegistrations.values.forEach {
            it.error("activity_destroyed", "UnifiedPush registration was interrupted.", null)
        }
        pendingRegistrations.clear()
        unifiedPushChannel = null
        backgroundPushChannel = null
        if (DeltiecordEngineRegistry.engine === configuredEngine) {
            DeltiecordEngineRegistry.engine = null
            DeltiecordEngineRegistry.pushBridgeReady = false
        }
        configuredEngine = null
        super.onDestroy()
    }
}
