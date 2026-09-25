package club.buildd.synk

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.lifecycle.Lifecycle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity keeps the Flutter engine shared with the background
// playback service so music continues with the screen off / app backgrounded.
//
// Picture-in-picture for videos (see lib/features/player/data/picture_in_picture.dart):
// Dart arms it while a video plays; leaving the app then shrinks it into the
// system PiP window instead of pausing the video.
class MainActivity : AudioServiceActivity() {
    private var pipChannel: MethodChannel? = null
    private var pipArmed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "club.buildd.synk/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAutoEnter" -> {
                        pipArmed = call.arguments as? Boolean ?: false
                        updatePipParams()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: the system enters PiP itself on Home / gesture nav,
            // with a smooth animation. Seamless resize off: it's video content.
            builder.setAutoEnterEnabled(pipArmed).setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (!pipSupported()) return
        pipParams()?.let { setPictureInPictureParams(it) }
    }

    // Screens the app opens itself (share sheet, links, sign-in) aren't the
    // user leaving: without this flag they'd trigger PiP (onUserLeaveHint on
    // 8–11, auto-enter on 12+). Home / Recents still do. startActivity(...)
    // overloads all route through here.
    override fun startActivityForResult(intent: Intent, requestCode: Int, options: Bundle?) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION)
        super.startActivityForResult(intent, requestCode, options)
    }

    // Android 8–11 has no auto-enter: go into PiP when the user leaves the app.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipArmed || !pipSupported() || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        pipParams()?.let { enterPictureInPictureMode(it) }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Closing the window stops the activity before this callback; expanding
        // it resumes the activity. Lets Dart stop the video instead of
        // resuming it the next time the app opens.
        val dismissed = !isInPictureInPictureMode && lifecycle.currentState == Lifecycle.State.CREATED
        pipChannel?.invokeMethod("changed", mapOf("inPip" to isInPictureInPictureMode, "dismissed" to dismissed))
    }
}
