package com.example.langkah_hackathon

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.location.Location
import android.os.Bundle
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// Runs only in the separate instrumentation APK; no test controls in Langkah.
class LocationChecks : Instrumentation() {
    private var expectMock = false
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        expectMock = arguments?.getString("expect_mock") == "true"
        start()
    }

    private class Reply : MethodChannel.Result {
        var value: Any? = null
        var code: String? = null
        var message: String? = null
        val completed = CountDownLatch(1)
        override fun success(result: Any?) { value = result; completed.countDown() }
        override fun error(errorCode: String, errorMessage: String?, details: Any?) {
            code = errorCode; message = errorMessage; completed.countDown()
        }
        override fun notImplemented() { error("NOT_IMPLEMENTED", null, null) }
    }

    override fun onStart() {
        val report = Bundle()
        var activity: Activity? = null
        try {
            runOnMainSync {
                val subject = MainActivity()
                val replyField = MainActivity::class.java.getDeclaredField("locationResult").apply { isAccessible = true }
                val receive = MainActivity::class.java.getDeclaredMethod("receiveLocation", Location::class.java).apply { isAccessible = true }
                val timeout = MainActivity::class.java.getDeclaredField("timeout").apply { isAccessible = true }.get(subject) as Runnable
                fun fix(accuracy: Float = 10f, ageSeconds: Long = 0, mock: Boolean = false) = Location("gps").apply {
                    latitude = 3.225; longitude = 101.73
                    this.accuracy = accuracy
                    elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos() - TimeUnit.SECONDS.toNanos(ageSeconds)
                    time = System.currentTimeMillis()
                    isMock = mock
                }
                fun begin() = Reply().also { replyField.set(subject, it) }
                var reply = begin()
                receive.invoke(subject, fix(mock = true))
                check(reply.code == "MOCK_LOCATION" && reply.message!!.contains("Developer options"))
                check(replyField.get(subject) == null)
                receive.invoke(subject, fix())
                check(reply.code == "MOCK_LOCATION") // A later callback cannot overwrite rejection.
                reply = begin()
                receive.invoke(subject, fix(ageSeconds = 16, mock = true))
                check(reply.completed.count == 1L) // Old mock cache permits a new genuine fix.
                receive.invoke(subject, fix())
                check(reply.code == null && (reply.value as Map<*, *>)["accuracy"] == 10.0)
                reply = begin()
                receive.invoke(subject, fix(ageSeconds = 16))
                check(reply.completed.count == 1L)
                timeout.run()
                check(reply.code == "LOCATION_TIMEOUT" && reply.message!!.contains("fresh location"))
                reply = begin()
                receive.invoke(subject, fix(accuracy = 100f))
                check(reply.completed.count == 1L)
                timeout.run()
                check(reply.code == "LOCATION_TIMEOUT" && reply.message!!.contains("not accurate enough"))
                reply = begin()
                receive.invoke(subject, fix(accuracy = 75f))
                check(reply.code == null && reply.value != null)
                reply = begin()
                receive.invoke(subject, fix(accuracy = Float.NaN))
                check(reply.completed.count == 1L)
                receive.invoke(subject, fix(accuracy = -1f))
                check(reply.completed.count == 1L)
                receive.invoke(subject, fix())
                check(reply.value != null)
            }
            report.putString("classification", "PASS: fresh mock, stale mock recovery, stale real, inaccurate timeout, valid real, accuracy boundary, invalid accuracy, late callback")

            // Also exercise the real Android provider path. Send emulator geo fixes while running.
            activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            val reply = Reply()
            val startedAt = SystemClock.elapsedRealtime()
            runOnMainSync {
                MainActivity::class.java.getDeclaredMethod("locate", MethodChannel.Result::class.java).apply { isAccessible = true }.invoke(activity, reply)
            }
            check(reply.completed.await(30, TimeUnit.SECONDS)) { "Native location reply never completed" }
            if (expectMock) {
                check(reply.code == "MOCK_LOCATION") { "Provider path: ${reply.code}: ${reply.message}" }
                check(SystemClock.elapsedRealtime() - startedAt < 5000) { "Mock rejection waited too long" }
                report.putString("provider", "PASS: actual device mock location rejected with actionable instructions")
            } else {
                check(reply.code == null && reply.value != null) { "Provider path: ${reply.code}: ${reply.message}" }
                report.putString("provider", "PASS: fresh precise location returned through Android LocationManager")
            }
            finish(Activity.RESULT_OK, report)
        } catch (e: Throwable) {
            report.putString("failure", e.stackTraceToString())
            finish(Activity.RESULT_CANCELED, report)
        } finally {
            activity?.let { runOnMainSync { it.finish() } }
        }
    }
}
