package br.sincrolocal.sincro_local

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import java.io.IOException
import java.util.UUID

class BlueLink(private val activity: MainActivity) {
    private val adapter: BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter
    private var server: BluetoothServerSocket? = null
    private var socket: BluetoothSocket? = null
    private val service = UUID.fromString("7a1b2c3d-4e5f-6789-abcd-ef0123456789")
    var message = "Bluetooth parado"
        private set

    fun available(): Boolean = adapter != null && adapter.isEnabled

    fun listen(payload: String) {
        val local = adapter ?: return
        Thread {
            try {
                server = local.listenUsingRfcommWithServiceRecord("SincroLocal", service)
                message = "Esperando o outro pelo Bluetooth..."
                val client = server?.accept()
                socket = client
                client?.outputStream?.write((payload + "\n").toByteArray())
                client?.outputStream?.flush()
                message = "Senha enviada pelo Bluetooth"
            } catch (_: IOException) {
                message = "Bluetooth não abriu"
            }
        }.start()
    }

    fun fetch(): String? {
        val local = adapter ?: return null
        return try {
            val device = local.bondedDevices.firstOrNull() ?: return null
            val client = device.createRfcommSocketToServiceRecord(service)
            client.connect()
            socket = client
            val text = client.inputStream.bufferedReader().readLine()
            message = "Senha recebida"
            text
        } catch (_: IOException) {
            message = "Não achei o outro pelo Bluetooth"
            null
        }
    }

    fun stop() {
        try { socket?.close() } catch (_: Exception) {}
        try { server?.close() } catch (_: Exception) {}
        socket = null
        server = null
        message = "Bluetooth parado"
    }
}
