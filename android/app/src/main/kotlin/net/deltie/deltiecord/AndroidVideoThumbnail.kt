package net.deltie.deltiecord

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import java.io.File
import java.io.FileOutputStream

/** Bounded, transient first-frame extraction for Matrix camera-video uploads. */
internal object AndroidVideoThumbnail {
    private const val MAX_SOURCE_BYTES = 128 * 1024 * 1024
    private const val MAX_RESULT_BYTES = 1024 * 1024

    fun generate(
        context: Context,
        bytes: ByteArray,
        mimeType: String?,
        maxDimension: Int,
    ): Map<String, Any>? {
        if (bytes.isEmpty() || bytes.size > MAX_SOURCE_BYTES) return null
        if (mimeType != null && !mimeType.startsWith("video/")) return null
        val source = File.createTempFile("video-probe-", ".media", context.cacheDir)
        return try {
            FileOutputStream(source).use { output -> output.write(bytes) }
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(source.absolutePath)
                val rawWidth = retriever.metadataInt(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                val rawHeight = retriever.metadataInt(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                val rotation = retriever.metadataInt(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) ?: 0
                val originalWidth = if (rotation == 90 || rotation == 270) rawHeight else rawWidth
                val originalHeight = if (rotation == 90 || rotation == 270) rawWidth else rawHeight
                val duration = retriever.metadataLong(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.coerceIn(0L, Int.MAX_VALUE.toLong())
                    ?.toInt()
                if (originalWidth == null || originalHeight == null ||
                    originalWidth <= 0 || originalHeight <= 0
                ) return null
                val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.getFrameAtTime(1_000_000, MediaMetadataRetriever.OPTION_CLOSEST)
                    ?: return null
                try {
                    val limit = maxDimension.coerceIn(64, 1024)
                    val scale = minOf(1.0, limit.toDouble() / maxOf(frame.width, frame.height))
                    val width = maxOf(1, (frame.width * scale).toInt())
                    val height = maxOf(1, (frame.height * scale).toInt())
                    val scaled = if (width == frame.width && height == frame.height) {
                        frame
                    } else {
                        Bitmap.createScaledBitmap(frame, width, height, true)
                    }
                    try {
                        val output = java.io.ByteArrayOutputStream()
                        if (!scaled.compress(Bitmap.CompressFormat.JPEG, 82, output)) return null
                        val thumbnail = output.toByteArray()
                        if (thumbnail.isEmpty() || thumbnail.size > MAX_RESULT_BYTES) return null
                        mapOf(
                            "bytes" to thumbnail,
                            "width" to width,
                            "height" to height,
                            "originalWidth" to originalWidth,
                            "originalHeight" to originalHeight,
                            "duration" to (duration ?: 0),
                        )
                    } finally {
                        if (scaled !== frame) scaled.recycle()
                    }
                } finally {
                    frame.recycle()
                }
            } finally {
                retriever.release()
            }
        } finally {
            source.delete()
        }
    }

    private fun MediaMetadataRetriever.metadataInt(key: Int): Int? =
        extractMetadata(key)?.toIntOrNull()

    private fun MediaMetadataRetriever.metadataLong(key: Int): Long? =
        extractMetadata(key)?.toLongOrNull()
}
