package com.example.townpass

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.example.townpass.location.LocationTrackingService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startLocationService()
                        result.success(null)
                    }

                    "stop" -> {
                        stopLocationService()
                        result.success(null)
                    }

                    "isRunning" -> result.success(isLocationServiceRunning())
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun startLocationService() {
        if (!isLocationServiceRunning()) {
            val intent = Intent(applicationContext, LocationTrackingService::class.java)
            ContextCompat.startForegroundService(applicationContext, intent)
        }
    }

    private fun stopLocationService() {
        val intent = Intent(applicationContext, LocationTrackingService::class.java)
        applicationContext.stopService(intent)
    }

    private fun isLocationServiceRunning(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        return manager.getRunningServices(Integer.MAX_VALUE).any {
            it.service.className == LocationTrackingService::class.java.name
        }
    }

    companion object {
        private const val LOCATION_METHOD_CHANNEL = "townpass/location_service"
        private const val LOCATION_EVENT_CHANNEL = "townpass/location_stream"

        @JvmStatic
        var eventSink: EventChannel.EventSink? = null

        @JvmStatic
        fun emitLocationUpdate(payload: Map<String, Any>) {
            eventSink?.success(payload)
        }
    }
}
