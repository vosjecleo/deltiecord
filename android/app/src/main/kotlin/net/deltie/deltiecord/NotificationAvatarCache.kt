package net.deltie.deltiecord

import android.content.Context
import android.graphics.Bitmap
import java.io.File
import java.security.MessageDigest

/** Private, bounded bridge between the Flutter session and background push. */
object NotificationAvatarCache {
    private const val DIRECTORY = "notification-avatars"
    private const val MAX_ENTRIES = 256
    private const val MAX_BYTES = 2 * 1024 * 1024

    fun put(context: Context, roomId: String, bytes: ByteArray): Boolean {
        if (
            roomId.isBlank() ||
            bytes.isEmpty() ||
            bytes.size > MAX_BYTES ||
            !NotificationBitmapDecoder.hasSafeBounds(bytes)
        ) return false
        val directory = File(context.cacheDir, DIRECTORY).apply { mkdirs() }
        val target = File(directory, key(roomId))
        val temporary = File(directory, "${target.name}.tmp")
        return runCatching {
            temporary.outputStream().use { it.write(bytes) }
            if (!temporary.renameTo(target)) {
                temporary.copyTo(target, overwrite = true)
                temporary.delete()
            }
            target.setLastModified(System.currentTimeMillis())
            trim(directory)
            true
        }.getOrElse {
            temporary.delete()
            false
        }
    }

    fun get(context: Context, roomId: String?): Bitmap? {
        if (roomId.isNullOrBlank()) return null
        val file = File(File(context.cacheDir, DIRECTORY), key(roomId))
        if (!file.isFile || file.length() !in 1..MAX_BYTES.toLong()) return null
        file.setLastModified(System.currentTimeMillis())
        return NotificationBitmapDecoder.decode(file, 192)
    }

    private fun trim(directory: File) {
        val files = directory.listFiles { file -> file.isFile && !file.name.endsWith(".tmp") }
            ?.sortedByDescending { it.lastModified() }
            ?: return
        files.drop(MAX_ENTRIES).forEach(File::delete)
    }

    private fun key(roomId: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(roomId.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
}
