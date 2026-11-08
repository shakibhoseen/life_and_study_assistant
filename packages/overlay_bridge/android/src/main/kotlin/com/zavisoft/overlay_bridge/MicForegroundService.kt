package com.zavisoft.overlay_bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * A foreground service whose only job is to carry Android's `microphone`
 * service type, and only for as long as the microphone is actually open.
 *
 * The floating bubble runs in a foreground service of its own which lives for
 * as long as the bubble is on screen. Giving that service the microphone type
 * made the app claim the microphone merely for showing a bubble. The type is
 * fixed in the manifest and the overlay plugin starts its service without one,
 * so it cannot be switched on and off there. This service is started around
 * the recording itself instead, and stopped as soon as it ends.
 */
class MicForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val notification = buildNotification(
            intent?.getStringExtra(EXTRA_TEXT) ?: DEFAULT_TEXT,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Deliberately not sticky. If the process is killed the microphone
        // goes with it, and a service the system restarted on its own would
        // claim the microphone again with nobody listening through it.
        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Microphone in use",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown only while the app is listening."
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val EXTRA_TEXT = "text"
        private const val CHANNEL_ID = "mic_foreground_service"
        private const val NOTIFICATION_ID = 0x4D49
        private const val DEFAULT_TEXT = "Listening"
    }
}
