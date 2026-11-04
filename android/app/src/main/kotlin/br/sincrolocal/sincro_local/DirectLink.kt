package br.sincrolocal.sincro_local

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.net.wifi.WifiConfiguration
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import java.net.Inet4Address
import java.net.NetworkInterface

class DirectLink(private val activity: MainActivity) {
    private val manager = activity.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    private var channel: WifiP2pManager.Channel? = null
    private var registered = false
    private val peers = mutableListOf<WifiP2pDevice>()
    private var info: WifiP2pInfo? = null
    private var ssid: String? = null
    private var passphrase: String? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var message = "Wi-Fi Direct parado"
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var hotspotIp: String? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> channel?.let { ch ->
                    manager?.requestPeers(ch) { list ->
                        peers.clear()
                        peers.addAll(list.deviceList)
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    info = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_INFO, WifiP2pInfo::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_INFO)
                    }
                    message = if (info?.groupFormed == true) "Rede direta formada" else "Aguardando a rede direta"
                    readGroup()
                }
            }
        }
    }

    fun permissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    fun allowed(): Boolean {
        return permissions().all {
            activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun ensure() {
        if (manager == null) return
        if (channel == null) channel = manager.initialize(activity, activity.mainLooper, null)
        if (!registered) {
            val filter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(receiver, filter)
            }
            registered = true
        }
    }

    fun rename(name: String) {
        ensure()
        val ch = channel ?: return
        val clean = name.trim().take(28).ifEmpty { "Sincro" }
        try {
            val method = manager?.javaClass?.getMethod(
                "setDeviceName",
                WifiP2pManager.Channel::class.java,
                String::class.java,
                WifiP2pManager.ActionListener::class.java,
            )
            method?.invoke(manager, ch, clean, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    message = "Nome deste aparelho: $clean"
                }
                override fun onFailure(reason: Int) {
                    message = "Não consegui gravar o nome ($reason)"
                }
            })
        } catch (_: Exception) {
            message = "Este Android não deixa mudar o nome da rede"
        }
    }

    fun own() {
        if (Build.VERSION.SDK_INT >= 26) {
            startHotspot()
            return
        }
        ensure()
        val ch = channel ?: return
        message = "Criando a rede direta..."
        @Suppress("DEPRECATION")
        manager?.createGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                message = "Rede direta criada. Mostre o QR."
                readGroup()
            }
            override fun onFailure(reason: Int) {
                message = "Não consegui criar a rede direta ($reason)"
            }
        })
    }

    @Suppress("DEPRECATION")
    private fun startHotspot() {
        if (Build.VERSION.SDK_INT < 26) return
        message = "Criando a rede..."
        val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspotReservation = reservation
                    val config = reservation.wifiConfiguration
                    ssid = config?.SSID?.removeSurrounding("\"")
                    passphrase = config?.preSharedKey?.removeSurrounding("\"")
                    message = "Rede criada. Pegando o IP..."
                    Handler(Looper.getMainLooper()).postDelayed({
                        hotspotIp = hotspotAddress()
                        message = if (hotspotIp != null) "Rede pronta. Mostre o QR." else "Rede criada, mas o IP ainda não apareceu."
                    }, 1500)
                }
                override fun onFailed(reason: Int) {
                    message = "Não consegui criar a rede ($reason)"
                }
                override fun onStopped() {
                    message = "Rede parada"
                    hotspotReservation = null
                    hotspotIp = null
                }
            }, Handler(Looper.getMainLooper()))
        } catch (error: Exception) {
            message = "Este aparelho não criou a rede: ${error.message}"
        }
    }

    private fun hotspotAddress(): String? {
        val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
        for (iface in interfaces) {
            val name = iface.name ?: continue
            if (name.startsWith("wlan") || name.startsWith("ap") || name.startsWith("swlan")) {
                for (addr in iface.inetAddresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val host = addr.hostAddress ?: continue
                        if (host.startsWith("192.168.")) return host
                    }
                }
            }
        }
        return null
    }

    fun find() {
        ensure()
        val ch = channel ?: return
        message = "Procurando aparelhos..."
        manager?.discoverPeers(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                message = "Procurando aparelhos por perto"
            }
            override fun onFailure(reason: Int) {
                message = "A busca direta falhou ($reason)"
            }
        })
    }

    fun joinNetwork(networkName: String, networkPass: String) {
        ensure()
        if (Build.VERSION.SDK_INT < 29) {
            message = "Este Android é antigo para entrar pelo QR."
            return
        }
        val ch = channel
        if (ch != null) manager?.cancelConnect(ch, null)
        val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        networkCallback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(networkName)
            .setWpa2Passphrase(networkPass)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                connectivity.bindProcessToNetwork(network)
                message = "Conectado na rede direta"
            }

            override fun onUnavailable() {
                message = "Não entrou na rede direta. Leia o QR outra vez."
            }
        }
        networkCallback = callback
        message = "Aceite a rede uma vez."
        connectivity.requestNetwork(request, callback)
    }

    fun stop() {
        hotspotReservation?.close()
        hotspotReservation = null
        hotspotIp = null
        val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        networkCallback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        networkCallback = null
        connectivity.bindProcessToNetwork(null)
        val ch = channel
        if (ch != null) {
            manager?.cancelConnect(ch, null)
            manager?.removeGroup(ch, null)
        }
        info = null
        ssid = null
        passphrase = null
        peers.clear()
        message = "Rede parada"
    }

    fun status(): Map<String, Any?> {
        readGroup()
        val owner = info?.groupOwnerAddress?.hostAddress
        val mine = hotspotIp ?: p2pAddress() ?: if (info?.isGroupOwner == true) owner else null
        return mapOf(
            "message" to message,
            "groupFormed" to (hotspotIp != null || info?.groupFormed == true),
            "isOwner" to (hotspotIp != null || info?.isGroupOwner == true),
            "ownerIp" to (hotspotIp ?: owner),
            "ip" to mine,
            "ssid" to ssid,
            "passphrase" to passphrase,
            "peers" to peers.map { mapOf("name" to it.deviceName, "address" to it.deviceAddress) },
        )
    }

    private fun readGroup() {
        val ch = channel ?: return
        manager?.requestGroupInfo(ch) { group ->
            if (group == null) return@requestGroupInfo
            ssid = group.networkName
            passphrase = group.passphrase
        }
    }

    private fun p2pAddress(): String? {
        val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
        for (iface in interfaces) {
            val name = iface.name ?: continue
            if (!name.startsWith("p2p")) continue
            for (addr in iface.inetAddresses) {
                if (addr is Inet4Address && !addr.isLoopbackAddress) return addr.hostAddress
            }
        }
        return null
    }
}
