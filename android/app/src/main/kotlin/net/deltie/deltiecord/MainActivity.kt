package net.deltie.deltiecord

import android.os.Handler
import android.os.Looper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.UnifiedPush
import java.util.concurrent.Executors
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "net.deltie.deltiecord/unified_push"
        private const val NOTIFICATION_ASSETS_CHANNEL =
            "net.deltie.deltiecord/notification_assets"
        private const val BACKGROUND_PUSH_CHANNEL =
            "net.deltie.deltiecord/background_push"
        private const val MEDIA_SAVER_CHANNEL =
            "net.deltie.deltiecord/media_saver"
        private const val VIDEO_THUMBNAIL_CHANNEL =
            "net.deltie.deltiecord/video_thumbnail"
        private const val SHARED_CONTENT_CHANNEL =
            "net.deltie.deltiecord/shared_content"
        private const val REGISTRATION_TIMEOUT_MS = 30_000L
        private const val MAX_SHARED_ITEM_BYTES = 32 * 1024 * 1024
        private const val MAX_SHARED_TOTAL_BYTES = 64 * 1024 * 1024
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val mediaSaveExecutor = Executors.newSingleThreadExecutor()
    private val pendingRegistrations = mutableMapOf<String, MethodChannel.Result>()
    private var unifiedPushChannel: MethodChannel? = null
    private var backgroundPushChannel: MethodChannel? = null
    private var configuredEngine: FlutterEngine? = null
    private var sharedContentChannel: MethodChannel? = null

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
        sharedContentChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARED_CONTENT_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "consume") {
                    result.success(consumeSharedContent(intent))
                } else {
                    result.notImplemented()
                }
            }
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
                "clearRoom" -> {
                    val roomId = call.argument<String>("roomId")
                    if (roomId.isNullOrBlank()) {
                        result.error("invalid_room", "Missing room identifier.", null)
                    } else {
                        DeltiecordNotificationPublisher.clearRoom(this, roomId)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SAVER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveMedia") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val suggestedName = call.argument<String>("suggestedName").orEmpty()
            val mimeType = call.argument<String>("mimeType").orEmpty()
            if (bytes == null || bytes.isEmpty()) {
                result.error("invalid_media", "Missing downloaded media data.", null)
                return@setMethodCallHandler
            }
            mediaSaveExecutor.execute {
                runCatching {
                    AndroidMediaSaver.save(this, bytes, suggestedName, mimeType)
                }.fold(
                    onSuccess = { savedName ->
                        mainHandler.post { result.success(savedName) }
                    },
                    onFailure = { exception ->
                        mainHandler.post {
                            result.error("save_failed", exception.message, null)
                        }
                    },
                )
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VIDEO_THUMBNAIL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "generate") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val mimeType = call.argument<String>("mimeType")
            val maxDimension = call.argument<Int>("maxDimension") ?: 800
            if (bytes == null || bytes.isEmpty()) {
                result.error("invalid_video", "Missing video data.", null)
                return@setMethodCallHandler
            }
            mediaSaveExecutor.execute {
                runCatching {
                    AndroidVideoThumbnail.generate(this, bytes, mimeType, maxDimension)
                }.fold(
                    onSuccess = { thumbnail -> mainHandler.post { result.success(thumbnail) } },
                    onFailure = { exception ->
                        mainHandler.post {
                            result.error("thumbnail_failed", exception.message, null)
                        }
                    },
                )
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
        notificationTarget(intent, clear = true)?.let { target ->
            backgroundPushChannel?.invokeMethod("onNotificationActivated", target)
        }
        if (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE) {
            sharedContentChannel?.invokeMethod("available", null)
        }
    }

    private fun consumeSharedContent(source: Intent?): Map<String, Any?>? {
        if (source?.action != Intent.ACTION_SEND && source?.action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }
        val text = source.getStringExtra(Intent.EXTRA_TEXT)?.take(100_000)
        val uris = sharedUris(source).take(10)
        var total = 0
        val items = mutableListOf<Map<String, Any>>()
        for (uri in uris) {
            val mimeType = contentResolver.getType(uri) ?: source.type ?: continue
            if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) continue
            val bytes = readBounded(uri, minOf(MAX_SHARED_ITEM_BYTES, MAX_SHARED_TOTAL_BYTES - total))
                ?: continue
            total += bytes.size
            items += mapOf(
                "bytes" to bytes,
                "mimeType" to mimeType,
                "name" to sharedDisplayName(uri, mimeType),
            )
            if (total >= MAX_SHARED_TOTAL_BYTES) break
        }
        source.action = null
        source.removeExtra(Intent.EXTRA_TEXT)
        source.removeExtra(Intent.EXTRA_STREAM)
        return mapOf("text" to text, "items" to items)
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(source: Intent): List<Uri> =
        if (source.action == Intent.ACTION_SEND_MULTIPLE) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                source.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
            } else {
                source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            }
        } else {
            val uri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                source.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            listOfNotNull(uri)
        }

    private fun readBounded(uri: Uri, limit: Int): ByteArray? {
        if (limit <= 0) return null
        return runCatching {
            contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream(minOf(limit, 256 * 1024))
                val chunk = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val read = input.read(chunk)
                    if (read < 0) break
                    total += read
                    if (total > limit) return null
                    output.write(chunk, 0, read)
                }
                output.toByteArray()
            }
        }.getOrNull()
    }

    private fun sharedDisplayName(uri: Uri, mimeType: String): String {
        runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) cursor.getString(index)?.takeIf { it.isNotBlank() }?.let { return it }
                    }
                }
        }
        val extension = when (mimeType) {
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "video/webm" -> "webm"
            else -> if (mimeType.startsWith("video/")) "mp4" else "bin"
        }
        return "shared-${System.currentTimeMillis()}.$extension"
    }

    override fun onResume() {
        super.onResume()
        DeltiecordEngineRegistry.appInForeground = true
        // Opening the app ends every prior notification burst. A later push
        // must be allowed to alert immediately after the app is backgrounded,
        // even when the previous alert was less than five minutes ago.
        DeltiecordNotificationPublisher.resetAlertCadenceOnAppOpen(this)
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
            DeltiecordNotificationPublisher.clearRoom(this, roomId)
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
        sharedContentChannel = null
        if (DeltiecordEngineRegistry.engine === configuredEngine) {
            DeltiecordEngineRegistry.engine = null
            DeltiecordEngineRegistry.pushBridgeReady = false
        }
        configuredEngine = null
        mediaSaveExecutor.shutdown()
        super.onDestroy()
    }
}
