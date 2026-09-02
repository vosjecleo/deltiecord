package net.deltie.deltiecord

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

/** Rejects compressed-image bombs before Android allocates their full bitmap. */
internal object NotificationBitmapDecoder {
    private const val MAX_DIMENSION = 4096
    private const val MAX_PIXELS = 8_000_000L

    fun hasSafeBounds(bytes: ByteArray): Boolean {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        return safe(options.outWidth, options.outHeight)
    }

    fun decode(file: File, targetDimension: Int): Bitmap? {
        if (!file.isFile) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (!safe(bounds.outWidth, bounds.outHeight)) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > targetDimension) {
            sample *= 2
        }
        return BitmapFactory.decodeFile(
            file.absolutePath,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }

    private fun safe(width: Int, height: Int): Boolean =
        width in 1..MAX_DIMENSION &&
            height in 1..MAX_DIMENSION &&
            width.toLong() * height.toLong() <= MAX_PIXELS
}
