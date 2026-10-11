package com.prs.localist

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.os.FileObserver
import android.provider.MediaStore
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Publishes completed engine downloads without widening the peer's storage sandbox. */
object RemoteReceivedFiles {
    const val ACTION = "com.prs.localist.REMOTE_FILE_RECEIVED"
    private val executor = Executors.newSingleThreadExecutor()
    private val observers = mutableMapOf<String, FileObserver>()
    private val downloads = mutableSetOf<String>()
    private val lock = Any()

    fun start(context: Context) {
        val app = context.applicationContext
        val root = app.getExternalFilesDir(null) ?: return
        executor.execute { watch(app, root.canonicalFile, root) }
    }

    private fun watch(context: Context, root: File, directory: File) {
        val canonical = directory.canonicalFile
        if (!canonical.toPath().startsWith(root.toPath()) || !canonical.isDirectory ||
            observers.containsKey(canonical.path)) return
        @Suppress("DEPRECATION")
        val observer = object : FileObserver(canonical.path, CREATE or MOVED_TO or MOVED_FROM or DELETE) {
            override fun onEvent(event: Int, path: String?) {
                if (path == null) return
                executor.execute {
                    runCatching {
                        val file = File(canonical, path)
                        val kind = event and ALL_EVENTS
                        if (file.isDirectory) {
                            if (kind == CREATE || kind == MOVED_TO) watch(context, root, file)
                        } else if (path.endsWith(".download")) {
                            if (kind == DELETE) downloads.remove(file.path.removeSuffix(".download"))
                            else downloads.add(file.path.removeSuffix(".download"))
                        } else if (kind == MOVED_TO && downloads.remove(file.path)) {
                            publish(context, root, file)
                        }
                    }.onFailure { Log.w("Localist", "Cannot publish completed remote file", it) }
                }
            }
        }
        observers[canonical.path] = observer
        observer.startWatching()
        canonical.listFiles()?.forEach {
            if (it.isDirectory) watch(context, root, it)
            else if (it.name.endsWith(".download")) downloads.add(it.path.removeSuffix(".download"))
        }
    }

    private fun publish(context: Context, root: File, source: File) {
        val file = source.canonicalFile
        require(file.toPath().startsWith(root.toPath()) && file.isFile)
        val id = UUID.randomUUID().toString()
        val stem = file.nameWithoutExtension.replace(Regex("[^\\p{L}\\p{N}._ -]"), "_")
            .take(80).ifBlank { "File" }
        val folder = "Localist/${stem}_${id.take(8)}"
        val destination = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "$folder/${file.name}")
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, file.name)
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$folder")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("Cannot create Downloads entry")
            try {
                resolver.openOutputStream(uri)?.use { output -> file.inputStream().use { it.copyTo(output) } }
                    ?: error("Cannot write Downloads entry")
                resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
            } catch (failure: Exception) {
                resolver.delete(uri, null, null)
                throw failure
            }
        } else {
            check(destination.parentFile?.mkdirs() == true || destination.parentFile?.isDirectory == true)
            file.copyTo(destination, overwrite = false)
        }
        val record = JSONObject().apply {
            put("id", "remote-$id")
            put("path", destination.absolutePath)
            put("fileName", file.name)
            put("totalBytes", file.length())
            put("updatedMs", System.currentTimeMillis())
        }
        synchronized(lock) {
            val prefs = context.getSharedPreferences("remote_received_files", Context.MODE_PRIVATE)
            val records = JSONArray(prefs.getString("records", "[]"))
            records.put(record)
            check(prefs.edit().putString("records", records.toString()).commit())
        }
        context.sendBroadcast(Intent(ACTION).setPackage(context.packageName))
    }

    fun pending(context: Context): List<Map<String, Any>> = synchronized(lock) {
        val records = JSONArray(context.getSharedPreferences("remote_received_files", Context.MODE_PRIVATE)
            .getString("records", "[]"))
        (0 until records.length()).map { index ->
            val item = records.getJSONObject(index)
            mapOf("id" to item.getString("id"), "path" to item.getString("path"),
                "fileName" to item.getString("fileName"), "totalBytes" to item.getLong("totalBytes"),
                "updatedMs" to item.getLong("updatedMs"))
        }
    }

    fun acknowledge(context: Context, ids: List<String>) = synchronized(lock) {
        val prefs = context.getSharedPreferences("remote_received_files", Context.MODE_PRIVATE)
        val records = JSONArray(prefs.getString("records", "[]"))
        val remaining = JSONArray()
        for (index in 0 until records.length()) {
            val item = records.getJSONObject(index)
            if (!ids.contains(item.getString("id"))) remaining.put(item)
        }
        check(prefs.edit().putString("records", remaining.toString()).commit())
    }
}
