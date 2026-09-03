package net.deltie.deltiecord

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Publishes bounded Android conversation notifications.
 *
 * Decrypted bodies and thumbnails arrive from the local Dart Matrix client;
 * credentials and encryption material never cross this boundary. Histories
 * are capped so the collapsed notification contains only the latest message,
 * while Android's MessagingStyle expansion reveals recent messages/media.
 */
object DeltiecordNotificationPublisher {
    private const val CHANNEL_ID = "deltiecord_messages_stable"
    private const val BACKGROUND_CHANNEL_ID = "deltiecord_background_sync"
    private const val PREFS = "deltiecord_notification_alerts"
    private const val HISTORY_DIRECTORY = "notification-history"
    private const val MAX_HISTORY_BYTES = 64 * 1024
    private const val MAX_MESSAGES = 6
    private const val MAX_MEDIA_BYTES = 3 * 1024 * 1024
    private const val MAX_AVATAR_BYTES = 1024 * 1024
    private const val ALERT_COOLDOWN_MS = 5L * 60 * 1000

    data class MessageData(
        val roomId: String,
        val eventId: String,
        val roomName: String,
        val senderName: String,
        val body: String,
        val timestamp: Long,
        val groupConversation: Boolean,
        val senderAvatar: ByteArray? = null,
        val image: ByteArray? = null,
        val imageMimeType: String? = null,
        val sound: Boolean = true,
        val vibrate: Boolean = true,
        val alertCadence: String = "fiveMinuteCooldown",
        val unreadCount: Int = 1,
    )

    fun fromMap(arguments: Map<*, *>): MessageData? {
        val roomId = arguments["roomId"] as? String ?: return null
        val eventId = arguments["eventId"] as? String ?: return null
        if (roomId.isBlank() || eventId.isBlank()) return null
        return MessageData(
            roomId = roomId.take(1024),
            eventId = eventId.take(1024),
            roomName = (arguments["roomName"] as? String).orEmpty().ifBlank { "Deltiecord" }.take(160),
            senderName = (arguments["senderName"] as? String).orEmpty().ifBlank { "Matrix user" }.take(160),
            body = (arguments["body"] as? String).orEmpty().ifBlank { "New message" }.take(4096),
            timestamp = (arguments["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis(),
            groupConversation = arguments["groupConversation"] as? Boolean ?: false,
            senderAvatar = (arguments["senderAvatar"] as? ByteArray)?.takeIf {
                it.size <= MAX_AVATAR_BYTES && NotificationBitmapDecoder.hasSafeBounds(it)
            },
            image = (arguments["image"] as? ByteArray)?.takeIf {
                it.size <= MAX_MEDIA_BYTES && NotificationBitmapDecoder.hasSafeBounds(it)
            },
            imageMimeType = (arguments["imageMimeType"] as? String)?.takeIf {
                it in setOf("image/jpeg", "image/png", "image/webp", "image/gif")
            },
            sound = arguments["sound"] as? Boolean ?: true,
            vibrate = arguments["vibrate"] as? Boolean ?: true,
            alertCadence = (arguments["alertCadence"] as? String)
                ?.takeIf { it in setOf("fiveMinuteCooldown", "everyMessage", "silent") }
                ?: "fiveMinuteCooldown",
            unreadCount = ((arguments["unreadCount"] as? Number)?.toInt() ?: 1)
                .coerceIn(0, MAX_MESSAGES),
        )
    }

    fun backgroundWorkNotification(context: Context): Notification {
        ensureBackgroundChannel(context)
        return builder(context, BACKGROUND_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Deltiecord")
            .setContentText("Decrypting a new message")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    fun cancelBackgroundWorkNotification(context: Context) {
        manager(context).cancel(9002)
    }

    fun publish(context: Context, data: MessageData) {
        val shouldAlert = shouldAlert(context, data)
        val channelId = channelId(data, shouldAlert)
        ensureChannel(context, channelId, data.sound && shouldAlert, data.vibrate && shouldAlert)
        val avatarPath = data.senderAvatar?.let {
            writeBoundedFile(context, "avatar", data.eventId, it, ".png")
        }
        val imagePath = data.image?.let {
            writeBoundedFile(context, "media", data.eventId, it, extensionFor(data.imageMimeType))
        }
        val history = loadHistory(context, data.roomId)
            .filterNot { it.optString("eventId") == data.eventId }
            .toMutableList()
        history += JSONObject().apply {
            put("eventId", data.eventId)
            put("roomName", data.roomName)
            put("senderName", data.senderName)
            put("body", data.body)
            put("timestamp", data.timestamp)
            put("groupConversation", data.groupConversation)
            put("avatarPath", avatarPath)
            put("imagePath", imagePath)
            put("imageMimeType", data.imageMimeType)
        }
        // Matrix is the source of truth for unread/highlight state. Native
        // history is only presentation cache and must never resurrect entries
        // that Matrix already considers read.
        val retainCount = data.unreadCount.coerceIn(1, MAX_MESSAGES)
        while (history.size > retainCount) history.removeAt(0)
        while (history.size > MAX_MESSAGES) history.removeAt(0)
        saveHistory(context, data.roomId, history)

        val latest = history.last()
        val latestAvatar = bitmapFromPath(latest.optString("avatarPath"))
        val conversationAvatar = NotificationAvatarCache.get(context, data.roomId)
            ?: latestAvatar
        val decoratedAvatar = conversationAvatar?.let { decorateAvatar(context, it) }
        val contentIntent = contentIntent(
            context,
            data.roomId,
            latest.optString("eventId"),
        )
        val shortcutId = ensureConversationShortcut(
            context,
            data,
            decoratedAvatar,
        )
        val notificationBuilder = builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(latest.optString("roomName", "Deltiecord"))
            .setContentText(latest.optString("body", "New message"))
            .setLargeIcon(decoratedAvatar)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setWhen(latest.optLong("timestamp", System.currentTimeMillis()))
            .setShowWhen(true)
            .setOnlyAlertOnce(!shouldAlert)
            .setStyle(messagingStyle(context, history, decoratedAvatar))
            .addAction(replyAction(context, data.roomId, latest.optString("eventId")))
            .addAction(simpleAction(context, data.roomId, latest.optString("eventId"), "read", "Mark read"))
            .addAction(simpleAction(context, data.roomId, latest.optString("eventId"), "mute", "Mute"))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationBuilder.setShortcutId(shortcutId)
        } else if (!shouldAlert) {
            @Suppress("DEPRECATION")
            notificationBuilder.setSound(null).setVibrate(longArrayOf())
        }
        val notification = notificationBuilder.build()
        manager(context).notify(data.roomId, 9001, notification)
        context.getSharedPreferences("deltiecord_unified_push", Context.MODE_PRIVATE)
            .edit()
            .putLong("last_notification_posted_ms", System.currentTimeMillis())
            .apply()
        cleanupFiles(context, history)
    }

    private fun replyAction(
        context: Context,
        roomId: String,
        eventId: String,
    ): Notification.Action {
        val input = RemoteInput.Builder(DeltiecordNotificationActionReceiver.KEY_REPLY)
            .setLabel("Reply")
            .build()
        return Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_notification),
            "Reply",
            actionIntent(context, roomId, eventId, "reply", mutable = true),
        )
            .addRemoteInput(input)
            .setAllowGeneratedReplies(true)
            .build()
    }

    private fun simpleAction(
        context: Context,
        roomId: String,
        eventId: String,
        action: String,
        label: String,
    ): Notification.Action = Notification.Action.Builder(
        Icon.createWithResource(context, R.drawable.ic_notification),
        label,
        actionIntent(context, roomId, eventId, action, mutable = false),
    ).build()

    private fun actionIntent(
        context: Context,
        roomId: String,
        eventId: String,
        action: String,
        mutable: Boolean,
    ): PendingIntent {
        val intent = Intent(context, DeltiecordNotificationActionReceiver::class.java).apply {
            data = Uri.parse(
                "deltiecord://notification-action/${StableIdentifier.digest("$roomId|$eventId|$action")}",
            )
            putExtra(DeltiecordNotificationActionReceiver.EXTRA_ROOM_ID, roomId)
            putExtra(DeltiecordNotificationActionReceiver.EXTRA_EVENT_ID, eventId)
            putExtra(DeltiecordNotificationActionReceiver.EXTRA_ACTION, action)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        flags = flags or if (mutable && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(
            context,
            StableIdentifier.requestCode("$roomId|$eventId|$action"),
            intent,
            flags,
        )
    }

    private fun shouldAlert(context: Context, data: MessageData): Boolean {
        if ((!data.sound && !data.vibrate) || data.alertCadence == "silent") return false
        if (data.alertCadence == "everyMessage") return true
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = "alert:${digest(data.roomId)}"
        val now = System.currentTimeMillis()
        val previous = preferences.getLong(key, 0)
        if (now - previous < ALERT_COOLDOWN_MS) return false
        preferences.edit().putLong(key, now).apply()
        return true
    }

    private fun channelId(data: MessageData, alert: Boolean): String = when {
        !alert -> "${CHANNEL_ID}_silent"
        data.sound && data.vibrate -> "${CHANNEL_ID}_sound_vibrate"
        data.sound -> "${CHANNEL_ID}_sound"
        else -> "${CHANNEL_ID}_vibrate"
    }

    private fun ensureConversationShortcut(
        context: Context,
        data: MessageData,
        avatar: Bitmap?,
    ): String {
        val shortcutId = "room-${digest(data.roomId)}"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return shortcutId
        val intent = Intent(context, MainActivity::class.java).apply {
            this.data = Uri.parse(
                "deltiecord://notification/${StableIdentifier.digest("${data.roomId}|${data.eventId}")}",
            )
            action = Intent.ACTION_VIEW
            putExtra("notification_room_id", data.roomId)
            putExtra("notification_event_id", data.eventId)
        }
        val builder = ShortcutInfo.Builder(context, shortcutId)
            .setShortLabel(data.roomName.take(40))
            .setLongLabel(data.roomName.take(80))
            .setIntent(intent)
        if (avatar != null) builder.setIcon(Icon.createWithBitmap(avatar))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setLongLived(true)
        runCatching {
            context.getSystemService(ShortcutManager::class.java)
                .addDynamicShortcuts(listOf(builder.build()))
        }
        return shortcutId
    }

    private fun messagingStyle(
        context: Context,
        history: List<JSONObject>,
        fallbackAvatar: Bitmap?,
    ): Notification.Style {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val self = android.app.Person.Builder().setName("You").build()
            val style = Notification.MessagingStyle(self)
                .setConversationTitle(history.last().optString("roomName", "Deltiecord"))
                .setGroupConversation(history.last().optBoolean("groupConversation", false))
            for (entry in history) {
                val bitmap = bitmapFromPath(entry.optString("avatarPath"))
                    ?.let(::circleAvatar)
                    ?: fallbackAvatar
                val personBuilder = android.app.Person.Builder()
                    .setName(entry.optString("senderName", "Matrix user"))
                if (bitmap != null) personBuilder.setIcon(Icon.createWithBitmap(bitmap))
                val message = Notification.MessagingStyle.Message(
                    entry.optString("body", "New message"),
                    entry.optLong("timestamp", System.currentTimeMillis()),
                    personBuilder.build(),
                )
                attachImage(context, message, entry)
                style.addMessage(message)
            }
            return style
        }
        @Suppress("DEPRECATION")
        val style = Notification.MessagingStyle("You")
            .setConversationTitle(history.last().optString("roomName", "Deltiecord"))
        for (entry in history) {
            @Suppress("DEPRECATION")
            val message = Notification.MessagingStyle.Message(
                entry.optString("body", "New message"),
                entry.optLong("timestamp", System.currentTimeMillis()),
                entry.optString("senderName", "Matrix user"),
            )
            attachImage(context, message, entry)
            style.addMessage(message)
        }
        return style
    }

    private fun attachImage(
        context: Context,
        message: Notification.MessagingStyle.Message,
        entry: JSONObject,
    ) {
        // MessagingStyle.Message.setData was added in API 28. Older Android
        // versions still receive the text conversation without risking a
        // verifier/runtime failure in the background receiver process.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        val path = entry.optString("imagePath").takeIf { it.isNotBlank() } ?: return
        val mime = entry.optString("imageMimeType").takeIf { it.startsWith("image/") } ?: return
        val file = File(path)
        if (!file.isFile || file.length() !in 1..MAX_MEDIA_BYTES.toLong()) return
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.notification_files",
            file,
        )
        grantSystemUiRead(context, uri)
        message.setData(mime, uri)
    }

    private fun grantSystemUiRead(context: Context, uri: Uri) {
        for (packageName in listOf("com.android.systemui", "android")) {
            runCatching {
                context.grantUriPermission(
                    packageName,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }
    }

    private fun decorateAvatar(context: Context, source: Bitmap): Bitmap {
        val output = circleAvatar(source)
        val canvas = Canvas(output)
        val size = output.width
        val badgeRadius = 37f
        val badgeCenter = size - badgeRadius
        canvas.drawCircle(
            badgeCenter,
            badgeCenter,
            badgeRadius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(30, 31, 36) },
        )
        val badge = BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher_round)
        if (badge != null) {
            canvas.drawBitmap(
                badge,
                null,
                RectF(
                    badgeCenter - 29,
                    badgeCenter - 29,
                    badgeCenter + 29,
                    badgeCenter + 29,
                ),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
            )
        }
        return output
    }

    private fun circleAvatar(source: Bitmap): Bitmap {
        val size = 192
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val scale = maxOf(size.toFloat() / source.width, size.toFloat() / source.height)
        val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        val matrix = android.graphics.Matrix().apply {
            setScale(scale, scale)
            postTranslate(
                (size - source.width * scale) / 2f,
                (size - source.height * scale) / 2f,
            )
        }
        shader.setLocalMatrix(matrix)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.shader = shader
        })

        return output
    }

    private fun bitmapFromPath(path: String): Bitmap? {
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.isFile || file.length() !in 1..MAX_AVATAR_BYTES.toLong()) return null
        return NotificationBitmapDecoder.decode(file, 192)
    }

    private fun writeBoundedFile(
        context: Context,
        directory: String,
        eventId: String,
        bytes: ByteArray,
        extension: String,
    ): String? = runCatching {
        val root = File(context.cacheDir, "notification-$directory").apply { mkdirs() }
        val file = File(root, "${digest(eventId)}$extension")
        if (!NotificationBitmapDecoder.hasSafeBounds(bytes)) return@runCatching null
        val temporary = File(root, ".${file.name}.${System.nanoTime()}.tmp")
        temporary.writeBytes(bytes)
        if (!temporary.renameTo(file)) {
            temporary.copyTo(file, overwrite = true)
            temporary.delete()
        }
        file.absolutePath
    }.getOrNull()

    private fun loadHistory(context: Context, roomId: String): List<JSONObject> = runCatching {
        val file = historyFile(context, roomId)
        if (!file.isFile || file.length() !in 1..MAX_HISTORY_BYTES.toLong()) {
            return@runCatching emptyList()
        }
        val raw = file.readText(Charsets.UTF_8)
        val array = JSONArray(raw)
        List(array.length()) { index -> array.getJSONObject(index) }
    }.getOrDefault(emptyList())

    private fun saveHistory(context: Context, roomId: String, history: List<JSONObject>) {
        val array = JSONArray()
        history.forEach(array::put)
        val raw = array.toString()
        if (raw.toByteArray(Charsets.UTF_8).size > MAX_HISTORY_BYTES) return
        val file = historyFile(context, roomId)
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, ".${file.name}.${System.nanoTime()}.tmp")
        temporary.writeText(raw, Charsets.UTF_8)
        if (!temporary.renameTo(file)) {
            temporary.copyTo(file, overwrite = true)
            temporary.delete()
        }
    }

    private fun cleanupFiles(context: Context, retained: List<JSONObject>) {
        val keep = retained.flatMap { entry ->
            listOf(entry.optString("avatarPath"), entry.optString("imagePath"))
        }.filter(String::isNotBlank).toSet()
        val cutoff = System.currentTimeMillis() - 48L * 60 * 60 * 1000
        for (directory in listOf("notification-avatar", "notification-media")) {
            File(context.cacheDir, directory).listFiles()?.forEach { file ->
                if (file.absolutePath !in keep && file.lastModified() < cutoff) file.delete()
            }
        }
    }

    private fun contentIntent(context: Context, roomId: String, eventId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("notification_room_id", roomId)
            putExtra("notification_event_id", eventId)
        }
        return PendingIntent.getActivity(
            context,
            StableIdentifier.requestCode("$roomId|$eventId"),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel(
        context: Context,
        channelId: String,
        sound: Boolean,
        vibrate: Boolean,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager(context).createNotificationChannel(
            NotificationChannel(
                channelId,
                "Messages",
                if (sound || vibrate) NotificationManager.IMPORTANCE_HIGH
                else NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Encrypted Matrix message notifications"
                enableVibration(vibrate)
                if (!sound) setSound(null, null)
                else setSound(Settings.System.DEFAULT_NOTIFICATION_URI, null)
            },
        )
    }

    private fun ensureBackgroundChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager(context).createNotificationChannel(
            NotificationChannel(
                BACKGROUND_CHANNEL_ID,
                "Background message processing",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Decrypts locally received Matrix notifications"
                setSound(null, null)
            },
        )
    }

    private fun builder(
        context: Context,
        channelId: String = CHANNEL_ID,
    ): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

    private fun manager(context: Context) =
        context.getSystemService(NotificationManager::class.java)

    private fun historyFile(context: Context, roomId: String) =
        File(File(context.cacheDir, HISTORY_DIRECTORY), "${digest(roomId)}.json")

    fun clearPrivateState(context: Context) {
        File(context.cacheDir, HISTORY_DIRECTORY).deleteRecursively()
        File(context.cacheDir, "notification-avatar").deleteRecursively()
        File(context.cacheDir, "notification-media").deleteRecursively()
        File(context.cacheDir, "notification-avatars").deleteRecursively()
        NotificationReplyStore.clear(context)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun clearRoom(context: Context, roomId: String) {
        loadHistory(context, roomId).forEach { entry ->
            entry.optString("avatarPath").takeIf(String::isNotBlank)?.let(::File)?.delete()
            entry.optString("imagePath").takeIf(String::isNotBlank)?.let(::File)?.delete()
        }
        historyFile(context, roomId).delete()
        manager(context).cancel(roomId, 9001)
    }

    private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .take(12)
        .joinToString("") { "%02x".format(it) }

    private fun extensionFor(mimeType: String?): String = when (mimeType) {
        "image/png" -> ".png"
        "image/webp" -> ".webp"
        "image/gif" -> ".gif"
        else -> ".jpg"
    }
}
