package br.sincrolocal.sincro_local

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "br.sincrolocal.sincro_local/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" -> result.success(hasAllFiles())
                    "requestAllFilesAccess" -> {
                        requestAllFiles()
                        result.success(null)
                    }
                    "deviceModel" -> result.success(Build.MODEL ?: "Este aparelho")
                    "wifiAddress" -> result.success(wifiAddress())
                    "volumes" -> result.success(volumes())
                    "hold" -> {
                        val intent = Intent(this, HoldService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    }
                    "release" -> {
                        stopService(Intent(this, HoldService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasAllFiles(): Boolean {
        return if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager() else true
    }

    private fun requestAllFiles() {
        if (Build.VERSION.SDK_INT < 30 || Environment.isExternalStorageManager()) return
        val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
        intent.data = Uri.parse("package:$packageName")
        startActivity(intent)
    }

    private fun wifiAddress(): String? {
        val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
        for (intf in interfaces) {
            for (addr in intf.inetAddresses) {
                if (addr.isLoopbackAddress || addr !is Inet4Address) continue
                val host = addr.hostAddress ?: continue
                if (host.startsWith("192.168.") || host.startsWith("10.") || host.startsWith("172.")) return host
            }
        }
        return null
    }

    private fun volumes(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val internal = Environment.getExternalStorageDirectory()
        if (internal != null && internal.exists()) {
            result.add(volume("Memória interna", internal, false))
        }
        File("/storage").listFiles()?.forEach { dir ->
            val name = dir.name
            if (name == "emulated" || name == "self" || name.startsWith(".")) return@forEach
            if (!dir.isDirectory) return@forEach
            result.add(volume("Cartão SD", dir, true))
        }
        return result
    }

    private fun volume(label: String, dir: File, removable: Boolean): Map<String, Any> {
        val stat = try {
            StatFs(dir.absolutePath)
        } catch (_: Exception) {
            null
        }
        return mapOf(
            "label" to label,
            "path" to dir.absolutePath,
            "freeBytes" to (stat?.availableBytes ?: 0L),
            "totalBytes" to (stat?.totalBytes ?: 0L),
            "removable" to removable,
            "fat32" to isFat(dir.absolutePath),
        )
    }

    private fun isFat(path: String): Boolean {
        return try {
            File("/proc/mounts").readLines().any { line ->
                val parts = line.split(" ")
                parts.size >= 3 && path.startsWith(parts[1]) && (parts[2] == "vfat" || parts[2] == "msdos")
            }
        } catch (_: Exception) {
            false
        }
    }
}
