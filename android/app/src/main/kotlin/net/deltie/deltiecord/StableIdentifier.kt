package net.deltie.deltiecord

import java.nio.ByteBuffer
import java.security.MessageDigest

/** Deterministic non-secret identifiers for persistent Android work/state. */
internal object StableIdentifier {
    fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }

    fun workName(prefix: String, value: String): String = "$prefix-${digest(value)}"

    // PendingIntent requires an Int. Its data URI also carries the full digest,
    // so this truncation is never the sole identity boundary.
    fun requestCode(value: String): Int = ByteBuffer.wrap(
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)),
    ).int and Int.MAX_VALUE
}
