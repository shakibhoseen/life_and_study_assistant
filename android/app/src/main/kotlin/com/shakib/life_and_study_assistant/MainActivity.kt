package com.shakib.life_and_study_assistant

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shakib.life_and_study_assistant/system_settings"

    companion object {
        var activeChannel: MethodChannel? = null

        fun requestWidgetRefresh() {
            val channel = activeChannel ?: return
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onWidgetRefreshRequested", null)
            }
        }

        fun requestStudyWidgetRefresh() {
            val channel = activeChannel ?: return
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onStudyWidgetRefreshRequested", null)
            }
        }

        /**
         * Where a widget tap wants to land.
         *
         * Widgets have always put a "route" extra on their intent and nothing
         * ever read it, so every tap opened the dashboard. Held here until
         * Dart asks for it, because the engine is not necessarily up when the
         * intent arrives.
         */
        var pendingRoute: String? = null
    }

    // Explicitly reference raw notification sounds so R8 and resource shrinker never strip them
    private val soundResources = intArrayOf(
        R.raw.meal_bell,
        R.raw.office_chime,
        R.raw.urgent_siren
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureRoute(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Tapping a widget while the app is already open arrives here, not in
        // onCreate, so both have to record it.
        captureRoute(intent)
        setIntent(intent)
        activeChannel?.let {
            Handler(Looper.getMainLooper()).post {
                it.invokeMethod("onPendingRouteAvailable", null)
            }
        }
    }

    private fun captureRoute(intent: Intent?) {
        val route = intent?.getStringExtra("route")
        if (!route.isNullOrEmpty()) pendingRoute = route
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        activeChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        } else {
                            Intent("android.settings.APP_NOTIFICATION_SETTINGS").apply {
                                putExtra("app_package", packageName)
                                putExtra("app_uid", applicationInfo.uid)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "openNotificationListenerSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "updateWidget" -> {
                    try {
                        OfficeStatusWidgetProvider.updateAllWidgets(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "updateStudyWidgets" -> {
                    try {
                        StudyWidgetSync.updateAll(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "consumePendingRoute" -> {
                    // Read once: a route already navigated to must not be
                    // replayed the next time the app is resumed.
                    val route = pendingRoute
                    pendingRoute = null
                    result.success(route)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (activeChannel != null) {
            activeChannel = null
        }
        super.onDestroy()
    }
}
