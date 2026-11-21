package org.localsend.localsend_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build

/**
 * Read-only radio snapshot. 5 GHz station support is NOT proof that this app
 * can configure a 5 GHz local-only hotspot; Android controls its SoftAP band.
 * Do not log SSIDs, passwords, network identifiers or access point BSSIDs.
 */
object ProWifiCapabilities {
    @SuppressLint("MissingPermission", "DEPRECATION")
    fun snapshot(context: Context): Map<String, Any?> {
        val manager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val supportsStation5GHz = try {
            manager?.is5GHzBandSupported ?: false
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }

        val frequencyMhz = try {
            manager?.connectionInfo?.frequency?.takeIf { it > 0 }
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }

        val band = when (frequencyMhz) {
            null -> "unknown"
            in 2400..2500 -> "2.4"
            in 4900..5925 -> "5"
            in 5926..7125 -> "6"
            else -> "unknown"
        }

        return mapOf(
            "supports5GHzStation" to supportsStation5GHz,
            // Public SDK cannot reliably promise a selectable 5 GHz hotspot.
            "supports5GHzHotspot" to null,
            "supportsLocalOnlyHotspot" to (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI)
                ),
            "supportsWifiDirect" to context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT),
            "currentFrequencyMHz" to frequencyMhz,
            "currentBand" to band
        )
    }
}
