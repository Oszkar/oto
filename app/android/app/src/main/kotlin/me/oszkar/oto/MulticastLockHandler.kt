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
 *
 * Robustness: the Wi-Fi service is looked up nullably (a device without
 * Wi-Fi returns null rather than crashing the engine at construction), and
 * lock operations are wrapped so a `SecurityException`/`RuntimeException`
 * surfaces as a structured MethodChannel error instead of tearing down the
 * Flutter engine. The Dart side treats any such failure as best-effort and
 * still attempts discovery.
 */
class MulticastLockHandler(context: Context) : MethodChannel.MethodCallHandler {
    // Nullable: `getSystemService(WifiManager::class.java)` returns null on a
    // device with no Wi-Fi service. (The older `as WifiManager` cast would
    // throw here, at handler construction = app launch.)
    private val wifiManager: WifiManager? =
        context.applicationContext.getSystemService(WifiManager::class.java)
    private var lock: WifiManager.MulticastLock? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                val wm = wifiManager
                if (wm == null) {
                    result.error("NO_WIFI_SERVICE", "WifiManager unavailable", null)
                    return
                }
                try {
                    val l = lock ?: wm.createMulticastLock("oto-ssdp").apply {
                        setReferenceCounted(true)
                    }.also { lock = it }
                    l.acquire()
                    result.success(null)
                } catch (e: RuntimeException) {
                    // SecurityException (missing CHANGE_WIFI_MULTICAST_STATE)
                    // or any other RuntimeException: report, don't crash.
                    result.error("ACQUIRE_FAILED", e.message, null)
                }
            }
            "release" -> {
                try {
                    // Guard against an unbalanced release (lock not held): the
                    // platform throws if released below zero references.
                    lock?.let { if (it.isHeld) it.release() }
                    result.success(null)
                } catch (e: RuntimeException) {
                    result.error("RELEASE_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
