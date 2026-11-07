package br.sincrolocal.sincro_local

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pendingMedia: MethodChannel.Result? = null
    private var pendingDirect: MethodChannel.Result? = null
    private var pendingDirectAction: (() -> Unit)? = null
    private val direct by lazy { DirectLink(this) }
    private val blue by lazy { BlueLink(this) }

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
                    "mediaAccess" -> result.success(mediaAccess())
                    "requestMediaAccess" -> requestMedia(result)
                    "openSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    "openHotspotSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                        } catch (_: Exception) {
                            openAppSettings()
                        }
                        result.success(null)
                    }
                    "gallery" -> {
                        val kind = call.argument<String>("kind") ?: "images"
                        val limit = call.argument<Int>("limit") ?: 250
                        val offset = call.argument<Int>("offset") ?: 0
                        Thread {
                            try {
                                val page = queryPage(kind, limit.coerceIn(1, 500), offset.coerceAtLeast(0))
                                runOnUiThread { result.success(page) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("gallery", error.message, null) }
                            }
                        }.start()
                    }
                    "stageMedia" -> {
                        val path = call.argument<String>("path")
                        val uri = call.argument<String>("uri")
                        Thread {
                            try {
                                val staged = stageMedia(path, uri)
                                runOnUiThread { result.success(staged) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("stage", error.message, null) }
                            }
                        }.start()
                    }
                    "deviceModel" -> result.success(Build.MODEL ?: "Este aparelho")
                    "wifiAddress" -> result.success(wifiAddress())
                    "volumes" -> result.success(volumes())
                    "multicast" -> {
                        val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                        val on = call.argument<Boolean>("on") == true
                        if (on) {
                            if (multicastLock == null) {
                                multicastLock = wifi.createMulticastLock("sincro").apply { setReferenceCounted(false) }
                            }
                            if (multicastLock?.isHeld != true) multicastLock?.acquire()
                        } else if (multicastLock?.isHeld == true) {
                            multicastLock?.release()
                        }
                        result.success(null)
                    }
                    "hold" -> {
                        val intent = Intent(this, HoldService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    }
                    "release" -> {
                        stopService(Intent(this, HoldService::class.java))
                        result.success(null)
                    }
                    "p2pStatus" -> result.success(direct.status())
                    "p2pOwn" -> startDirect(result) { direct.own() }
                    "p2pName" -> startDirect(result) { direct.rename(call.argument<String>("name") ?: "Sincro") }
                    "p2pJoinNet" -> {
                        val ssid = call.argument<String>("ssid") ?: ""
                        val pass = call.argument<String>("pass") ?: ""
                        direct.joinNetwork(ssid, pass)
                        result.success(true)
                    }
                    "p2pStop" -> {
                        direct.stop()
                        blue.stop()
                        result.success(null)
                    }
                    "blueListen" -> {
                        val payload = call.argument<String>("payload") ?: ""
                        blue.listen(payload)
                        result.success(true)
                    }
                    "blueFetch" -> {
                        Thread {
                            val text = blue.fetch()
                            runOnUiThread { result.success(text) }
                        }.start()
                    }
                    "blueStatus" -> result.success(blue.message)
                    "blueStop" -> {
                        blue.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startDirect(result: MethodChannel.Result, action: () -> Unit) {
        if (!direct.allowed()) {
            if (pendingDirect != null) {
                result.success(false)
                return
            }
            pendingDirect = result
            pendingDirectAction = action
            requestPermissions(direct.permissions(), 45823)
            return
        }
        action()
        result.success(true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 45823) {
            if (direct.allowed()) pendingDirectAction?.invoke()
            pendingDirect?.success(direct.allowed())
            pendingDirect = null
            pendingDirectAction = null
            return
        }
        if (requestCode != 45822) return
        pendingMedia?.success(mediaAccess() != "none")
        pendingMedia = null
    }

    private fun granted(permission: String): Boolean {
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun mediaPerms(): Array<String> {
        return if (Build.VERSION.SDK_INT >= 34) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
        } else if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
            )
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun mediaAccess(): String {
        if (Build.VERSION.SDK_INT >= 33) {
            val images = granted(Manifest.permission.READ_MEDIA_IMAGES)
            val videos = granted(Manifest.permission.READ_MEDIA_VIDEO)
            if (images && videos) return "all"
            val partial = Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            if (partial || images || videos) return "partial"
            return "none"
        }
        if (Build.VERSION.SDK_INT < 23) return "all"
        return if (granted(Manifest.permission.READ_EXTERNAL_STORAGE)) "all" else "none"
    }

    private fun requestMedia(result: MethodChannel.Result) {
        if (mediaAccess() == "all") {
            result.success(true)
            return
        }
        if (pendingMedia != null) {
            result.success(false)
            return
        }
        pendingMedia = result
        requestPermissions(mediaPerms(), 45822)
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        intent.data = Uri.parse("package:$packageName")
        startActivity(intent)
    }

    private fun isGalleryName(name: String): Boolean {
        val lower = name.lowercase()
        return listOf(".jpg", ".jpeg", ".png", ".heic", ".webp", ".gif", ".bmp", ".dng", ".mp4", ".mov", ".mkv", ".3gp", ".webm")
            .any { lower.endsWith(it) }
    }

    private fun categoryName(name: String): String {
        val lower = name.lowercase()
        return when {
            listOf(".pdf", ".doc", ".docx", ".txt", ".xls", ".xlsx", ".ppt", ".pptx", ".rtf").any { lower.endsWith(it) } -> "Documentos"
            listOf(".zip", ".rar", ".7z", ".tar", ".gz").any { lower.endsWith(it) } -> "Arquivos"
            listOf(".apk", ".apks", ".xapk").any { lower.endsWith(it) } -> "Aplicativos"
            listOf(".mp3", ".m4a", ".aac", ".wav", ".ogg", ".flac").any { lower.endsWith(it) } -> "Áudio"
            else -> "Downloads"
        }
    }

    private fun queryPage(kind: String, limit: Int, offset: Int): Map<String, Any> {
        val uri = when (kind) {
            "videos" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            "files" -> MediaStore.Files.getContentUri("external")
            else -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val fixedCategory = when (kind) {
            "videos" -> "Vídeos"
            "audio" -> "Áudio"
            "files" -> null
            else -> "Fotos"
        }
        val selection = if (kind == "files") {
            "${MediaStore.Files.FileColumns.MEDIA_TYPE}!=${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE} AND " +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE}!=${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}"
        } else {
            null
        }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATA,
        )
        val args = Bundle().apply {
            putInt(android.content.ContentResolver.QUERY_ARG_OFFSET, offset)
            putInt(android.content.ContentResolver.QUERY_ARG_LIMIT, limit)
            putStringArray(android.content.ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(MediaStore.MediaColumns.DATE_ADDED))
            putInt(
                android.content.ContentResolver.QUERY_ARG_SORT_DIRECTION,
                android.content.ContentResolver.QUERY_SORT_DIRECTION_DESCENDING,
            )
            if (selection != null) putString(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
        }
        val cursor = try {
            if (Build.VERSION.SDK_INT >= 26) {
                contentResolver.query(uri, projection, args, null)
            } else {
                contentResolver.query(
                    uri,
                    projection,
                    selection,
                    null,
                    "${MediaStore.MediaColumns.DATE_ADDED} DESC LIMIT $limit OFFSET $offset",
                )
            }
        } catch (_: Exception) {
            null
        } ?: return mapOf("files" to emptyList<Map<String, Any>>(), "next" to offset, "done" to true)
        val rows = mutableListOf<Map<String, Any>>()
        var visited = 0
        cursor.use {
            val idCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val dataCol = it.getColumnIndex(MediaStore.MediaColumns.DATA)
            while (it.moveToNext()) {
                visited++
                val id = it.getLong(idCol)
                val name = it.getString(nameCol)?.takeIf { value -> value.isNotBlank() } ?: "arquivo"
                val bytes = if (it.isNull(sizeCol)) 0L else it.getLong(sizeCol)
                if (!name.startsWith(".") && bytes > 0 && (kind != "files" || !isGalleryName(name))) {
                    val path = if (dataCol >= 0) it.getString(dataCol) ?: "" else ""
                    val content = android.content.ContentUris.withAppendedId(uri, id).toString()
                    rows.add(
                        mapOf(
                            "path" to path.ifEmpty { content },
                            "name" to name,
                            "bytes" to bytes,
                            "category" to (fixedCategory ?: categoryName(name)),
                            "uri" to content,
                        ),
                    )
                }
            }
        }
        return mapOf(
            "files" to rows,
            "next" to (offset + visited),
            "done" to (visited < limit),
        )
    }

    private fun stageMedia(path: String?, uri: String?): String {
        if (!path.isNullOrEmpty() && path.startsWith("/")) {
            val file = File(path)
            if (file.exists() && file.canRead() && file.length() > 0) return file.absolutePath
        }
        if (uri.isNullOrEmpty()) throw IllegalStateException("sem caminho legível")
        val parsed = Uri.parse(uri)
        val dir = File(cacheDir, "sincro-stage").apply { mkdirs() }
        val dest = File(dir, "${uri.hashCode().toUInt()}-${parsed.lastPathSegment ?: "item"}")
        if (dest.exists() && dest.length() > 0) return dest.absolutePath
        contentResolver.openInputStream(parsed)?.use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("não abriu o arquivo")
        return dest.absolutePath
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
        val seen = mutableSetOf<String>()
        fun add(label: String, dir: File?, removable: Boolean) {
            if (dir == null || !dir.exists() || !dir.isDirectory) return
            val path = dir.absolutePath
            if (!seen.add(path)) return
            result.add(volume(label, dir, removable))
        }
        add("Memória interna", Environment.getExternalStorageDirectory(), false)
        if (Build.VERSION.SDK_INT >= 24) {
            val manager = getSystemService(StorageManager::class.java)
            for (storage in manager.storageVolumes) {
                val dir = storage.directory ?: continue
                add(if (storage.isRemovable) "Cartão SD" else "Memória interna", dir, storage.isRemovable)
            }
        }
        File("/storage").listFiles()?.forEach { dir ->
            val name = dir.name
            if (name == "emulated" || name == "self" || name.startsWith(".")) return@forEach
            add("Cartão SD", dir, true)
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
