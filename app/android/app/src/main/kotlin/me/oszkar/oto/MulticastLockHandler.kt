package me.oszkar.oto

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Acquires/releases a [WifiManager.MulticastLock] around oto's discovery
 * SSDP window. Without a held lock Android silently drops inbound multicast
 * (the SSDP M-SEARCH replies from Sonos), so release-build discovery finds
 * nothing — debug/profile builds happen to work because Flutter tooling
 * supplies extra networking leniency. v0.5 S3.
 *
 * Reference-counted ([setReferenceCounted]) so balanced acquire/release
 * pairs from the Dart side nest correctly; the lock is held only for the
 * brief discovery window (not continuously) to avoid battery drain.
 */
class MulticastLockHandler(context: Context) : MethodChannel.MethodCallHandler {
    private val wifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private var lock: WifiManager.MulticastLock? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                if (lock == null) {
                    lock = wifiManager.createMulticastLock("oto-ssdp").apply {
                        setReferenceCounted(true)
                    }
                }
                lock?.acquire()
                result.success(null)
            }
            "release" -> {
                // Guard against an unbalanced release (lock not held): the
                // platform throws if released below zero references.
                lock?.let { if (it.isHeld) it.release() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
