package com.zavisoft.overlay_bridge

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The small Android bridge the floating bubble needs.
 *
 * Two jobs, both of which the bubble cannot do from Dart alone: starting and
 * stopping [MicForegroundService], and bringing the app itself to the front.
 */
class OverlayBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> result.success(start(call.argument<String>("text")))
            "stop" -> {
                stop()
                result.success(true)
            }
            "openApp" -> result.success(openApp())
            else -> result.notImplemented()
        }
    }

    private fun start(text: String?): Boolean {
        val intent = Intent(context, MicForegroundService::class.java)
        if (text != null) intent.putExtra(MicForegroundService.EXTRA_TEXT, text)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (e: Exception) {
            // Android 12 and up refuse a foreground service started from the
            // background unless the app is exempt, and holding
            // SYSTEM_ALERT_WINDOW -- which the bubble needs anyway -- is one of
            // those exemptions. Reported rather than thrown: the microphone
            // still works from the app's own screens, so a failure here must
            // not take the recording down with it.
            Log.w(TAG, "Could not start the microphone service", e)
            false
        }
    }

    /**
     * Brings the app to the front from the overlay.
     *
     * The bubble floats over whatever the user is doing, so there is no way
     * back to the app from it. `flutter_overlay_window` offers nothing for
     * this, hence the launch intent here. FLAG_ACTIVITY_NEW_TASK is required
     * because this is called from a service, and SINGLE_TOP reuses the
     * activity that is already there rather than stacking another copy on
     * top of it, which would lose whatever screen the user was last on.
     */
    private fun openApp(): Boolean {
        return try {
            val intent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?: return false
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Could not open the app", e)
            false
        }
    }

    private fun stop() {
        try {
            context.stopService(Intent(context, MicForegroundService::class.java))
        } catch (e: Exception) {
            Log.w(TAG, "Could not stop the microphone service", e)
        }
    }

    private companion object {
        const val CHANNEL_NAME = "overlay_bridge"
        const val TAG = "MicForegroundService"
    }
}
