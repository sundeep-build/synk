package club.buildd.synk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel

// Rings for an incoming huddle: someone started one in the room the user is
// in. Dart decides when and how (lib/features/rooms/application/huddle_ring_controller.dart):
// * app on screen: the ringtone alone, under Synk's own full-screen page;
// * app in the background or phone locked: a call notification that rings
//   until answered, declined or timed out. It opens full screen over the lock
//   screen (MainActivity shows itself there), or shows heads-up while the
//   phone is in use, or on Android 14+ without the full-screen permission.
object HuddleRinger {
    const val EXTRA_ACTION = "club.buildd.synk.huddle_ring"
    const val ACTION_OPEN = "open"
    const val ACTION_ACCEPT = "accept"

    private const val TAG = "HuddleRinger"
    private const val CHANNEL_ID = "club.buildd.synk.huddle_ring"
    private const val NOTIFICATION_ID = 7202

    // HuddleRules.ringTime in Dart. A safety net: Dart normally cancels first.
    private const val RING_FOR_MS = 30_000L
    private val VIBRATION = longArrayOf(0, 800, 1200)
    private val PENDING_FLAGS = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    private val RINGTONE_AUDIO = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** Dart side, for the notification's Decline button (HuddleRingReceiver). Set by MainActivity. */
    var channel: MethodChannel? = null

    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    fun show(context: Context, caller: String, room: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)
        val open = activityIntent(context, ACTION_OPEN, 1)
        val accept = activityIntent(context, ACTION_ACCEPT, 2)
        val decline = PendingIntent.getBroadcast(context, 3, Intent(context, HuddleRingReceiver::class.java), PENDING_FLAGS)
        try {
            manager.notify(NOTIFICATION_ID, build(context, caller, room, open, accept, decline, callStyle = true))
        } catch (e: IllegalArgumentException) {
            // Call style was refused (it insists on a full-screen intent or a
            // foreground service). Plain buttons do the same job.
            Log.w(TAG, "Call-style notification refused", e)
            manager.notify(NOTIFICATION_ID, build(context, caller, room, open, accept, decline, callStyle = false))
        }
    }

    fun cancel(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
    }

    /** The ringtone and vibration alone, following silent / vibrate mode. */
    fun startRingtone(context: Context) {
        stopRingtone()
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audio.ringerMode == AudioManager.RINGER_MODE_SILENT) return
        if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            ringtone = RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))?.apply {
                audioAttributes = RINGTONE_AUDIO
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
        }
        vibrator = vibratorOf(context).also {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                it.vibrate(VibrationEffect.createWaveform(VIBRATION, 0), RINGTONE_AUDIO)
            } else {
                @Suppress("DEPRECATION")
                it.vibrate(VIBRATION, 0, RINGTONE_AUDIO)
            }
        }
    }

    fun stopRingtone() {
        ringtone?.stop()
        ringtone = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun build(
        context: Context,
        caller: String,
        room: String,
        open: PendingIntent,
        accept: PendingIntent,
        decline: PendingIntent,
        callStyle: Boolean,
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID).setTimeoutAfter(RING_FOR_MS)
        } else {
            // Before channels, sound and priority are set per notification.
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_MAX)
                .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), RINGTONE_AUDIO)
                .setVibrate(VIBRATION)
        }
        val name = caller.ifEmpty { "Someone" }
        builder
            .setSmallIcon(R.drawable.ic_stat_huddle)
            .setContentTitle("$name started a huddle")
            .setContentText(room.ifEmpty { "Tap to answer" })
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .setOngoing(true)
            .setShowWhen(false)
        if (callStyle && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val person = Person.Builder().setName(name).setImportant(true).build()
            builder.setStyle(Notification.CallStyle.forIncomingCall(person, decline, accept))
        } else {
            val icon = Icon.createWithResource(context, R.drawable.ic_stat_huddle)
            builder
                .addAction(Notification.Action.Builder(icon, "Decline", decline).build())
                .addAction(Notification.Action.Builder(icon, "Join", accept).build())
        }
        // Rings on a loop until answered, declined or cancelled.
        return builder.build().apply { flags = flags or Notification.FLAG_INSISTENT }
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Huddle calls", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Rings when someone starts a huddle in your room"
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), RINGTONE_AUDIO)
                enableVibration(true)
                vibrationPattern = VIBRATION
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(false)
            },
        )
    }

    private fun activityIntent(context: Context, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_ACTION, action)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PENDING_FLAGS,
        )

    private fun vibratorOf(context: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
}

/** The call notification's Decline button: stops ringing and tells Dart. */
class HuddleRingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        HuddleRinger.cancel(context)
        HuddleRinger.channel?.invokeMethod("action", "decline")
    }
}
