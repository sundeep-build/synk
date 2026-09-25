package club.buildd.synk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

// Keeps the microphone working while Synk is in the background during a
// huddle. Android 11+ gives background mic access only to apps running a
// foreground service of type "microphone", started while the app is visible.
// Started and stopped from Dart: lib/features/huddle/data/huddle_foreground_service.dart.
class HuddleService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification(intent?.getStringExtra(EXTRA_ROOM).orEmpty())
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // The huddle still works while the app is open.
            Log.w(TAG, "Couldn't start the huddle foreground service", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Swiping the app away ends the call's background access with it.
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        stopSelf()
    }

    private fun buildNotification(room: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Huddles", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while you're in a huddle"
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_huddle)
            .setContentTitle("In a huddle")
            .setContentText(room.ifEmpty { "Tap to go back" })
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .build()
    }

    companion object {
        private const val TAG = "HuddleService"
        private const val CHANNEL_ID = "club.buildd.synk.huddle"
        private const val NOTIFICATION_ID = 7201
        private const val EXTRA_ROOM = "room"

        fun start(context: Context, room: String) {
            val intent = Intent(context, HuddleService::class.java).putExtra(EXTRA_ROOM, room)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, HuddleService::class.java))
        }
    }
}
