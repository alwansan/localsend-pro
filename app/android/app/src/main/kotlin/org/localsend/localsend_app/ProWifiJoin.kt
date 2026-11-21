package org.localsend.localsend_app

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

/**
 * Receiver-side, user-approved association with a Pro local-only hotspot.
 *
 * This intentionally NEVER binds the whole process to the new network: doing
 * so would silently redirect unrelated LocalSend traffic and could break a
 * working LAN session. A later authenticated transfer coordinator must bind
 * individual Rust sockets to the returned Network and verify reachability.
 * Credentials stay only in transient MethodChannel arguments, never logs.
 */
class ProWifiJoin {
    private val main = Handler(Looper.getMainLooper())
    private var manager: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var activeNetwork: Network? = null
    private var pending: MethodChannel.Result? = null

    @SuppressLint("MissingPermission")
    fun join(context: Context, ssid: String, passphrase: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "Local-only Wi-Fi requests require Android 10+", null)
            return
        }
        if (ssid.isBlank() || ssid.toByteArray(Charsets.UTF_8).size > 32 || passphrase.length !in 8..63) {
            result.error("INVALID_CREDENTIALS", "Invalid local Wi-Fi SSID or WPA2 passphrase", null)
            return
        }
        if (callback != null) {
            result.error("ALREADY_REQUESTED", "A Pro Wi-Fi request is already active", null)
            return
        }

        val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (connectivity == null) {
            result.error("NO_CONNECTIVITY", "Connectivity service unavailable", null)
            return
        }

        try {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(passphrase)
                .build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()

            val networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    main.post {
                        if (callback !== this) return@post
                        activeNetwork = network
                        val ipv4 = connectivity.getLinkProperties(network)
                            ?.linkAddresses
                            ?.firstOrNull { it.address is Inet4Address }
                            ?.address
                            ?.hostAddress
                        pending?.success(mapOf(
                            "connected" to true,
                            "networkHandle" to network.networkHandle.toString(),
                            "localIpv4" to ipv4
                        ))
                        pending = null
                    }
                }

                override fun onUnavailable() {
                    main.post {
                        if (callback !== this) return@post
                        val outstanding = pending
                        pending = null
                        release()
                        outstanding?.error("NETWORK_UNAVAILABLE", "Android could not join the local Wi-Fi network", null)
                    }
                }

                override fun onLost(network: Network) {
                    main.post {
                        if (callback !== this || activeNetwork != null && activeNetwork != network) return@post
                        val outstanding = pending
                        pending = null
                        release()
                        outstanding?.error("NETWORK_LOST", "Local Wi-Fi network was lost", null)
                    }
                }
            }

            manager = connectivity
            callback = networkCallback
            pending = result
            // Android shows its own consent dialog. No forced network switch.
            connectivity.requestNetwork(request, networkCallback, main, 45000)
        } catch (error: Exception) {
            val outstanding = pending
            pending = null
            release()
            (outstanding ?: result).error("NETWORK_REQUEST_FAILED", error.message ?: "Could not request local Wi-Fi", null)
        }
    }

    fun status(): Map<String, Any?> {
        val network = activeNetwork
        return mapOf(
            "connected" to (network != null),
            "networkHandle" to network?.networkHandle?.toString()
        )
    }

    /** Release our app's request; do not modify the device's default network. */
    fun leave() {
        val outstanding = pending
        pending = null
        release()
        outstanding?.error("CANCELLED", "Pro Wi-Fi request was cancelled", null)
    }

    private fun release() {
        val oldManager = manager
        val oldCallback = callback
        activeNetwork = null
        callback = null
        manager = null
        if (oldManager != null && oldCallback != null) {
            try {
                oldManager.unregisterNetworkCallback(oldCallback)
            } catch (_: Exception) {
                // Callback may already have been released by Android.
            }
        }
    }
}
