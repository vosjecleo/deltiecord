package net.deltie.deltiecord

import android.app.NotificationManager
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Queues privacy-preserving notification actions through the Matrix worker. */
class DeltiecordNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val roomId = intent.getStringExtra(EXTRA_ROOM_ID) ?: return
        val action = intent.getStringExtra(EXTRA_ACTION) ?: return
        if (action == ACTION_DISMISS) {
            // Dismissing an alert ends the current notification burst. The
            // next message should alert even when the five-minute cadence has
            // not elapsed, while retained unread history stays available.
            DeltiecordNotificationPublisher.invalidateRoomAlertState(context, roomId)
            return
        }
        val eventId = intent.getStringExtra(EXTRA_EVENT_ID) ?: return
        val reply = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(KEY_REPLY)
            ?.toString()
        DeltiecordPushWorker.enqueueAction(context, roomId, eventId, action, reply)
        DeltiecordNotificationPublisher.clearRoom(context, roomId)
        context.getSystemService(NotificationManager::class.java)
            .cancel(roomId, 9001)
    }

    companion object {
        const val EXTRA_ROOM_ID = "room_id"
        const val EXTRA_EVENT_ID = "event_id"
        const val EXTRA_ACTION = "action"
        const val KEY_REPLY = "reply_text"
        const val ACTION_DISMISS = "dismiss"
    }
}
