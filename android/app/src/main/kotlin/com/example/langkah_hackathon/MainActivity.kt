package com.example.langkah_hackathon

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private lateinit var sensors: SensorManager
    private var sink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private var permissionRequest = 0
    private var locationResult: MethodChannel.Result? = null
    private var locationListener: LocationListener? = null
    private var locationTooInaccurate = false
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable {
        finishLocation(null, if (locationTooInaccurate)
            "Your location is not accurate enough yet. Enable Precise location for Langkah and try near the mall entrance."
        else "Could not get a fresh location. Check that Location and Google Location Accuracy are on, then try near the mall entrance.", "LOCATION_TIMEOUT")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "langkah/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepAwake" -> {
                    if (call.argument<Boolean>("enabled") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                "requestActivity" -> {
                    if (sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) == null) {
                        result.error("NO_SENSOR", "This phone has no hardware step counter. Walking rewards require a supported phone.", null)
                    } else if (Build.VERSION.SDK_INT >= 29 && checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
                        requestAccess(101, arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), result)
                    } else result.success(true)
                }
                "location" -> {
                    if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                        requestAccess(102, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), result)
                    } else locate(result)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (!url.startsWith("https://www.simedarbyproperty.com/")) {
                        result.error("URL", "Only official mall directory links are supported", null)
                    } else try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        result.success(true)
                    } catch (e: Exception) { result.error("URL", "No browser is available to open the directory", null) }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "langkah/steps").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                val sensor = sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                if (sensor == null) events?.error("NO_SENSOR", "Step sensor unavailable", null)
                else if (Build.VERSION.SDK_INT >= 29 && checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
                    events?.error("PERMISSION", "Activity permission is required", null)
                } else if (!sensors.registerListener(this@MainActivity, sensor, SensorManager.SENSOR_DELAY_NORMAL)) {
                    events?.error("SENSOR_FAILED", "Could not start the step sensor", null)
                }
            }
            override fun onCancel(arguments: Any?) {
                sensors.unregisterListener(this@MainActivity)
                sink = null
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        })
    }
    private fun requestAccess(code: Int, permissions: Array<String>, result: MethodChannel.Result) {
        if (permissionResult != null) { result.error("BUSY", "A permission request is already open", null); return }
        permissionResult = result; permissionRequest = code
        requestPermissions(permissions, code)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        val result = permissionResult ?: return
        permissionResult = null
        if (grantResults.isEmpty() || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION", "Permission denied. Enable it in Android Settings to use real walking.", null)
        } else if (requestCode == 102) locate(result) else result.success(true)
    }
    @Suppress("MissingPermission")
    private fun locate(result: MethodChannel.Result) {
        if (locationResult != null) { result.error("BUSY", "Location is already being checked", null); return }
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).filter { manager.isProviderEnabled(it) }
        if (providers.isEmpty()) { result.error("LOCATION_OFF", "Enable your phone's location service", null); return }
        val cached = try { providers.mapNotNull { manager.getLastKnownLocation(it) }.filter { freshLocation(it) }
        } catch (e: Exception) { result.error("LOCATION", "Precise location permission is required", null); return }
        locationResult = result
        locationTooInaccurate = false
        // Prefer a usable real fix; stale cached mock fixes must not block recovery.
        cached.sortedBy { if (!mockLocation(it) && accurateLocation(it)) it.accuracy else Float.MAX_VALUE }
            .forEach { receiveLocation(it) }
        if (locationResult == null) return
        locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                receiveLocation(location)
            }
            @Deprecated("Deprecated in Java") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        try {
            providers.forEach { manager.requestLocationUpdates(it, 1000L, 0f, locationListener!!, Looper.getMainLooper()) }
            handler.postDelayed(timeout, 20000)
        } catch (e: Exception) { finishLocation(null, "Could not read location. Check permissions and try again.") }
    }
    private fun freshLocation(l: Location) = SystemClock.elapsedRealtimeNanos() - l.elapsedRealtimeNanos in 0..15_000_000_000L
    @Suppress("DEPRECATION")
    private fun mockLocation(l: Location) = if (Build.VERSION.SDK_INT >= 31) l.isMock else l.isFromMockProvider
    private fun accurateLocation(l: Location) = l.hasAccuracy() && l.accuracy.isFinite() && l.accuracy in 0f..75f
    private fun receiveLocation(l: Location) {
        if (locationResult == null || !freshLocation(l)) return
        if (mockLocation(l)) {
            finishLocation(null, "Mock location detected. Stop your location-changing app and set Select mock location app to None in Android Developer options, then retry at the mall.", "MOCK_LOCATION")
        } else if (accurateLocation(l)) finishLocation(l, null)
        else locationTooInaccurate = true
    }
    private fun locationMap(l: Location) = mapOf("latitude" to l.latitude, "longitude" to l.longitude, "accuracy" to l.accuracy.toDouble(), "age_ms" to (SystemClock.elapsedRealtimeNanos() - l.elapsedRealtimeNanos) / 1_000_000L)
    private fun finishLocation(location: Location?, error: String?, code: String = "LOCATION") {
        handler.removeCallbacks(timeout)
        locationListener?.let { (getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(it) }
        locationListener = null
        val result = locationResult; locationResult = null
        if (location != null) result?.success(locationMap(location)) else result?.error(code, error, null)
    }
    override fun onSensorChanged(event: SensorEvent) { sink?.success(event.values[0].toInt()) }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onDestroy() { sensors.unregisterListener(this); sink = null; finishLocation(null, "Check-in interrupted"); super.onDestroy() }
}
