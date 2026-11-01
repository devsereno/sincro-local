package br.sincrolocal.sincro_local

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
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
    private var message = "Wi-Fi Direct parado"

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

    fun own() {
        ensure()
        val ch = channel ?: return
        message = "Criando a rede direta..."
        @Suppress("DEPRECATION")
        manager?.createGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                message = "Rede direta criada. Esperando o outro aparelho."
            }
            override fun onFailure(reason: Int) {
                message = "Não consegui criar a rede direta ($reason)"
            }
        })
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

    fun join(address: String) {
        ensure()
        val ch = channel ?: return
        val config = WifiP2pConfig().apply { deviceAddress = address }
        message = "Conectando direto..."
        manager?.connect(ch, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                message = "Pedido enviado. Aceite no outro aparelho se ele pedir."
            }
            override fun onFailure(reason: Int) {
                message = "Não conectou direto ($reason)"
            }
        })
    }

    fun stop() {
        val ch = channel
        if (ch != null) manager?.removeGroup(ch, null)
        info = null
        peers.clear()
        message = "Wi-Fi Direct parado"
    }

    fun status(): Map<String, Any?> {
        val owner = info?.groupOwnerAddress?.hostAddress
        val mine = p2pAddress() ?: if (info?.isGroupOwner == true) owner else null
        return mapOf(
            "message" to message,
            "groupFormed" to (info?.groupFormed == true),
            "isOwner" to (info?.isGroupOwner == true),
            "ownerIp" to owner,
            "ip" to mine,
            "peers" to peers.map { mapOf("name" to it.deviceName, "address" to it.deviceAddress) },
        )
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
