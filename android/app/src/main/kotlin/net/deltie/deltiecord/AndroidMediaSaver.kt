package net.deltie.deltiecord

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.IOException

/** Writes explicit user downloads without requesting broad filesystem access. */
internal object AndroidMediaSaver {
    private const val DIRECTORY = "Deltiecord"
    private const val MAX_FILENAME_LENGTH = 180

    fun save(
        context: Context,
        bytes: ByteArray,
        suggestedName: String,
        mimeType: String,
    ): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IOException("Saving to Downloads requires Android 10 or newer.")
        }
        if (bytes.isEmpty()) throw IOException("The downloaded file is empty.")
        val safeMimeType = mimeType
            .takeIf { it.matches(Regex("^[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+$")) }
            ?: "application/octet-stream"
        val displayName = safeFilename(suggestedName, safeMimeType)
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, safeMimeType)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/$DIRECTORY",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("Android could not create the download.")
        try {
            resolver.openOutputStream(uri, "w")?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: throw IOException("Android could not open the download.")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return displayName
        } catch (exception: Throwable) {
            resolver.delete(uri, null, null)
            throw exception
        }
    }

    private fun safeFilename(suggestedName: String, mimeType: String): String {
        var name = suggestedName
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[\\u0000-\\u001f\\u007f]"), "")
            .trim()
            .trim('.')
        if (name.isBlank() || name == ".nomedia") {
            name = "deltiecord-${System.currentTimeMillis()}.${extensionFor(mimeType)}"
        }
        if (!name.contains('.')) name += ".${extensionFor(mimeType)}"
        return name.take(MAX_FILENAME_LENGTH)
    }

    private fun extensionFor(mimeType: String): String = when (mimeType.lowercase()) {
        "image/jpeg" -> "jpg"
        "image/png" -> "png"
        "image/gif" -> "gif"
        "image/webp" -> "webp"
        "video/mp4" -> "mp4"
        "video/webm" -> "webm"
        "audio/mpeg" -> "mp3"
        "audio/ogg" -> "ogg"
        else -> "bin"
    }
}
