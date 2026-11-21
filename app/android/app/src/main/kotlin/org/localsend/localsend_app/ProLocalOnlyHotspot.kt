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
 */
class ProLocalOnlyHotspot {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var starting = false

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

        starting = true
        try {
            manager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(active: WifiManager.LocalOnlyHotspotReservation) {
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
                    if (ssid.isNullOrBlank() || passphrase.isNullOrBlank()) {
                        stop()
                        result.error("NO_CREDENTIALS", "Android did not return hotspot credentials", null)
                        return
                    }
                    result.success(mapOf(
                        "ssid" to ssid,
                        "passphrase" to passphrase,
                        "band" to "system_selected"
                    ))
                }

                override fun onStopped() {
                    starting = false
                    reservation = null
                }

                override fun onFailed(reason: Int) {
                    starting = false
                    reservation = null
                    result.error("HOTSPOT_FAILED", "Android rejected local-only hotspot request ($reason)", null)
                }
            }, Handler(Looper.getMainLooper()))
        } catch (error: SecurityException) {
            starting = false
            result.error("PERMISSION_DENIED", "Wi-Fi hotspot permission denied", null)
        } catch (error: Exception) {
            starting = false
            result.error("HOTSPOT_FAILED", error.message ?: "Android hotspot could not start", null)
        }
    }

    fun stop() {
        reservation?.close()
        reservation = null
        starting = false
    }
}
