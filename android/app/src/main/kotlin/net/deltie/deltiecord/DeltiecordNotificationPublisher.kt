package net.deltie.deltiecord

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
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
    private const val CHANNEL_ID = "deltiecord_messages"
    private const val BACKGROUND_CHANNEL_ID = "deltiecord_background_sync"
    private const val PREFS = "deltiecord_notification_history"
    private const val MAX_MESSAGES = 6
    private const val MAX_MEDIA_BYTES = 3 * 1024 * 1024
    private const val MAX_AVATAR_BYTES = 1024 * 1024

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
            senderAvatar = (arguments["senderAvatar"] as? ByteArray)?.takeIf { it.size <= MAX_AVATAR_BYTES },
            image = (arguments["image"] as? ByteArray)?.takeIf { it.size <= MAX_MEDIA_BYTES },
            imageMimeType = (arguments["imageMimeType"] as? String)?.takeIf { it.startsWith("image/") },
            sound = arguments["sound"] as? Boolean ?: true,
        )
    }

    fun showPlaceholder(
        context: Context,
        roomId: String?,
        eventId: String?,
        title: String,
    ) {
        ensureBackgroundChannel(context)
        val targetRoom = roomId?.takeIf { it.isNotBlank() } ?: "unknown"
        val intent = contentIntent(context, targetRoom, eventId.orEmpty())
        val builder = builder(context, BACKGROUND_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title.take(160))
            .setContentText("New message")
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(intent)
        manager(context).notify(targetRoom, 9001, builder.build())
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

    fun publish(context: Context, data: MessageData) {
        ensureChannel(context)
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
        while (history.size > MAX_MESSAGES) history.removeAt(0)
        saveHistory(context, data.roomId, history)

        val latest = history.last()
        val latestAvatar = bitmapFromPath(latest.optString("avatarPath"))
        val decoratedAvatar = latestAvatar?.let { decorateAvatar(context, it) }
        val contentIntent = contentIntent(
            context,
            data.roomId,
            latest.optString("eventId"),
        )
        val notification = builder(context)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(latest.optString("roomName", "Deltiecord"))
            .setContentText(latest.optString("body", "New message"))
            .setLargeIcon(decoratedAvatar)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setWhen(latest.optLong("timestamp", System.currentTimeMillis()))
            .setShowWhen(true)
            .setOnlyAlertOnce(false)
            .setStyle(messagingStyle(context, history, decoratedAvatar))
            .build()
        manager(context).notify(data.roomId, 9001, notification)
        cleanupFiles(context, history)
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
                    ?.let { decorateAvatar(context, it) }
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

    private fun bitmapFromPath(path: String): Bitmap? {
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.isFile || file.length() !in 1..MAX_AVATAR_BYTES.toLong()) return null
        return BitmapFactory.decodeFile(path)
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
        file.writeBytes(bytes)
        file.absolutePath
    }.getOrNull()

    private fun loadHistory(context: Context, roomId: String): List<JSONObject> = runCatching {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(historyKey(roomId), null) ?: return@runCatching emptyList()
        val array = JSONArray(raw)
        List(array.length()) { index -> array.getJSONObject(index) }
    }.getOrDefault(emptyList())

    private fun saveHistory(context: Context, roomId: String, history: List<JSONObject>) {
        val array = JSONArray()
        history.forEach(array::put)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(historyKey(roomId), array.toString())
            .apply()
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
            roomId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager(context).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Messages",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Encrypted Matrix message notifications" },
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

    private fun historyKey(roomId: String) = "room:${digest(roomId)}"

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
