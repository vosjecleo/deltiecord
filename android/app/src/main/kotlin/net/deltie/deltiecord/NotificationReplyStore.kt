package net.deltie.deltiecord

import android.content.Context
import java.io.File
import java.util.UUID

/**
 * Keeps quick-reply plaintext out of WorkManager's persistent database.
 * Files live in the no-backup directory, are single-use, and expire quickly.
 */
internal object NotificationReplyStore {
    private const val DIRECTORY = "notification-replies"
    private const val MAX_CHARACTERS = 8_000
    private const val MAX_AGE_MS = 60L * 60 * 1000

    fun put(context: Context, reply: String?): String? {
        val value = reply?.take(MAX_CHARACTERS)?.takeIf { it.isNotBlank() } ?: return null
        val directory = File(context.noBackupFilesDir, DIRECTORY).apply { mkdirs() }
        cleanup(directory)
        val token = UUID.randomUUID().toString()
        val target = File(directory, token)
        return runCatching {
            target.createNewFile()
            target.setReadable(false, false)
            target.setWritable(false, false)
            target.setReadable(true, true)
            target.setWritable(true, true)
            target.writeText(value, Charsets.UTF_8)
            token
        }.getOrElse {
            target.delete()
            null
        }
    }

    fun consume(context: Context, token: String?): String? {
        if (token.isNullOrBlank() || !token.matches(Regex("[0-9a-f-]{36}"))) return null
        val file = File(File(context.noBackupFilesDir, DIRECTORY), token)
        if (!file.isFile || file.length() !in 1..32_000) return null
        return runCatching { file.readText(Charsets.UTF_8).take(MAX_CHARACTERS) }
            .getOrNull()
    }

    fun delete(context: Context, token: String?) {
        if (token.isNullOrBlank()) return
        File(File(context.noBackupFilesDir, DIRECTORY), token).delete()
    }

    fun clear(context: Context) {
        File(context.noBackupFilesDir, DIRECTORY).deleteRecursively()
    }

    private fun cleanup(directory: File) {
        val cutoff = System.currentTimeMillis() - MAX_AGE_MS
        directory.listFiles()?.filter { it.lastModified() < cutoff }?.forEach(File::delete)
    }
}
