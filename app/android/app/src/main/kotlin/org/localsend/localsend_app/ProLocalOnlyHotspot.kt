package org.localsend.localsend_app

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * User-initiated LocalOnlyHotspot lifecycle. This does NOT enable internet
 * tethering, connect the receiver automatically, or force the 5 GHz band.
 * Never log or persist its SSID/passphrase.
 *
 * A cancelled start can complete asynchronously. Each callback is scoped to
 * its generation, so stale results cannot re-open an abandoned hotspot.
 */
class ProLocalOnlyHotspot {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var starting = false
    private var generation = 0
    private var pending: MethodChannel.Result? = null

    @SuppressLint("MissingPermission", "DEPRECATION")
    fun start(context: Context, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "Local-only hotspots require Android 8 or newer", null)
            return
        }
        if (reservation != null || starting) {
            result.error("ALREADY_STARTED", "Pro local-only hotspot already active or starting", null)
            return
        }
        val manager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (manager == null) {
            result.error("NO_WIFI", "Wi-Fi service unavailable", null)
            return
        }

        generation++
        val requestGeneration = generation
        starting = true
        pending = result
        try {
            manager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(active: WifiManager.LocalOnlyHotspotReservation) {
                    if (requestGeneration != generation) {
                        active.close()
                        return
                    }
                    starting = false
                    reservation = active
                    val ssid: String?
                    val passphrase: String?
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val config = active.softApConfiguration
                        ssid = config.ssid
                        passphrase = config.passphrase
                    } else {
                        ssid = active.wifiConfiguration?.SSID?.trim('"')
                        passphrase = active.wifiConfiguration?.preSharedKey?.trim('"')
                    }
                    val receiver = pending
                    pending = null
                    if (ssid.isNullOrBlank() || passphrase.isNullOrBlank()) {
                        stop()
                        receiver?.error("NO_CREDENTIALS", "Android did not return hotspot credentials", null)
                        return
                    }
                    receiver?.success(mapOf(
                        "ssid" to ssid,
                        "passphrase" to passphrase,
                        "band" to "system_selected"
                    ))
                }

                override fun onStopped() {
                    if (requestGeneration != generation) return
                    val receiver = pending
                    pending = null
                    starting = false
                    reservation = null
                    receiver?.error("HOTSPOT_STOPPED", "Local hotspot was stopped before readiness", null)
                }

                override fun onFailed(reason: Int) {
                    if (requestGeneration != generation) return
                    val receiver = pending
                    pending = null
                    starting = false
                    reservation = null
                    receiver?.error("HOTSPOT_FAILED", "Android rejected local-only hotspot request ($reason)", null)
                }
            }, Handler(Looper.getMainLooper()))
        } catch (error: SecurityException) {
            starting = false
            pending = null
            result.error("PERMISSION_DENIED", "Wi-Fi hotspot permission denied", null)
        } catch (error: Exception) {
            starting = false
            pending = null
            result.error("HOTSPOT_FAILED", error.message ?: "Android hotspot could not start", null)
        }
    }

    fun stop() {
        generation++
        val receiver = pending
        pending = null
        starting = false
        val active = reservation
        reservation = null
        active?.close()
        receiver?.error("CANCELLED", "Local hotspot request cancelled", null)
    }
}
