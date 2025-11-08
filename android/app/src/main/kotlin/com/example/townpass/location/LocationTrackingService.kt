package com.example.townpass.location

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.townpass.MainActivity
import com.example.townpass.R
import com.google.android.gms.location.*
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

class LocationTrackingService : Service() {

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }
    private val retentionMillis = TimeUnit.MINUTES.toMillis(2) // Align with Flutter duration

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        println("[LocationTrackingService] onCreate")
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                println("[LocationTrackingService] onLocationResult: ${locationResult.locations.size} locations")
                val location = locationResult.lastLocation ?: return
                val capturedAt = dateFormat.format(Date())
                saveLocation(location.latitude, location.longitude, capturedAt)
                emitLocation(location.latitude, location.longitude, capturedAt)
            }
        }
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        println("[LocationTrackingService] onStartCommand")
        startForeground(NOTIFICATION_ID, buildNotification())
        requestLocationUpdates()
        return START_STICKY
    }

    override fun onDestroy() {
        println("[LocationTrackingService] onDestroy")
        fusedLocationClient.removeLocationUpdates(locationCallback)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun requestLocationUpdates() {
        if (!hasLocationPermission()) {
            println("[LocationTrackingService] missing location permission")
            return
        }

        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            TimeUnit.SECONDS.toMillis(10)
        ).setWaitForAccurateLocation(false)
            .setMinUpdateIntervalMillis(TimeUnit.SECONDS.toMillis(5))
            .setMinUpdateDistanceMeters(0f)
            .build()

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                mainLooper
            )
            println("[LocationTrackingService] requestLocationUpdates registered")
        } catch (error: SecurityException) {
            // Missing permission
            println("[LocationTrackingService] requestLocationUpdates failed: $error")
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val background = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        println("[LocationTrackingService] hasLocationPermission fine=$fine background=$background")
        return fine && background
    }

    private fun emitLocation(latitude: Double, longitude: Double, capturedAt: String) {
        val payload = hashMapOf(
            "latitude" to latitude,
            "longitude" to longitude,
            "capturedAt" to capturedAt
        )
        MainActivity.emitLocationUpdate(payload)
    }

    private fun saveLocation(latitude: Double, longitude: Double, capturedAt: String) {
        val prefs = getSharedPreferences(FLUTTER_SHARED_PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(PREFS_KEY, "[]") ?: "[]"
        val jsonArray = JSONArray(existing)
        val now = Date()
        val filtered = JSONArray()
        for (index in 0 until jsonArray.length()) {
            val item = jsonArray.optJSONObject(index) ?: continue
            val timestamp = item.optString("capturedAt")
            val date = parseDate(timestamp)
            if (date != null && now.time - date.time <= retentionMillis) {
                filtered.put(item)
            }
        }
        val newEntry = JSONObject().apply {
            put("latitude", latitude)
            put("longitude", longitude)
            put("capturedAt", capturedAt)
        }
        filtered.put(newEntry)
        prefs.edit().putString(PREFS_KEY, filtered.toString()).apply()
        println("[LocationTrackingService] saveLocation -> total=${filtered.length()}")
    }

    private fun parseDate(value: String): Date? {
        return try {
            dateFormat.parse(value)
        } catch (_: Exception) {
            null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_location),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.notification_channel_location_description)
                setShowBadge(false)
            }
            val service = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            service.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_content))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "location_tracking_channel"
        private const val NOTIFICATION_ID = 4127
        private const val FLUTTER_SHARED_PREFS = "FlutterSharedPreferences"
        private const val PREFS_KEY = "flutter.location_history_cache"
    }
}

