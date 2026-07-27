package com.music.player.playback

import android.content.Context
import android.util.Log
import com.music.player.data.settings.AudioQualityPreferences
import com.music.player.ui.util.SongDownloader
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

/**
 * Memory + disk URL cache so cold starts and offline retries can reuse resolved stream links.
 * Disk entries expire after [DISK_TTL_MS]; local file:// entries are validated on read.
 */
class SongUrlCache(context: Context) {

    private val appContext = context.applicationContext
    private val memory = object : LinkedHashMap<String, String>(MAX_MEMORY, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>): Boolean =
            size > MAX_MEMORY
    }
    private val diskFile = File(appContext.filesDir, "song_url_cache.json")
    private val lock = Any()
    private val pendingDisk = ConcurrentHashMap<String, String>()

    init {
        // Disk restore off the calling thread so coordinator init does not jank the UI.
        Thread {
            try {
                loadDisk()
            } catch (t: Throwable) {
                Log.w(TAG, "async load disk cache failed", t)
            }
        }.apply {
            name = "song-url-cache-load"
            isDaemon = true
            start()
        }
    }

    fun get(songId: String, source: String): String? {
        val key = cacheKey(songId, source)
        synchronized(lock) {
            memory[key]?.let { cached ->
                if (isUsable(cached)) return cached
                memory.remove(key)
            }
        }
        return null
    }

    fun put(songId: String, source: String, url: String) {
        val normalized = url.trim()
        if (normalized.isBlank()) return
        val key = cacheKey(songId, source)
        synchronized(lock) {
            memory[key] = normalized
        }
        pendingDisk[key] = normalized
        schedulePersist()
    }

    fun clear() {
        synchronized(lock) {
            memory.clear()
        }
        pendingDisk.clear()
        runCatching { diskFile.delete() }
    }

    private fun isUsable(url: String): Boolean {
        if (SongDownloader.isLocalFileUrl(url)) {
            return SongDownloader.isPlayableLocalUrl(url)
        }
        return url.isNotBlank()
    }

    private fun cacheKey(songId: String, source: String): String {
        val level = AudioQualityPreferences.getPreferredLevel(appContext)
        return "$source|$songId|${level.storageValue}"
    }

    private fun loadDisk() {
        if (!diskFile.isFile) return
        runCatching {
            val root = JSONObject(diskFile.readText(Charsets.UTF_8))
            val now = System.currentTimeMillis()
            val entries = root.optJSONObject("entries") ?: return
            val keys = entries.keys()
            synchronized(lock) {
                while (keys.hasNext()) {
                    val key = keys.next()
                    val item = entries.optJSONObject(key) ?: continue
                    val savedAt = item.optLong("t", 0L)
                    if (now - savedAt > DISK_TTL_MS) continue
                    val url = item.optString("u").trim()
                    if (url.isNotBlank() && isUsable(url)) {
                        memory[key] = url
                    }
                }
            }
        }.onFailure {
            Log.w(TAG, "load disk cache failed", it)
        }
    }

    private fun schedulePersist() {
        // Debounced by coalescing into pendingDisk; flush async on background thread.
        Thread {
            try {
                flushPending()
            } catch (t: Throwable) {
                Log.w(TAG, "persist url cache failed", t)
            }
        }.apply {
            name = "song-url-cache"
            isDaemon = true
            start()
        }
    }

    private fun flushPending() {
        if (pendingDisk.isEmpty()) return
        val snapshot = HashMap(pendingDisk)
        pendingDisk.keys.removeAll(snapshot.keys)
        val root = runCatching {
            if (diskFile.isFile) JSONObject(diskFile.readText(Charsets.UTF_8)) else JSONObject()
        }.getOrElse { JSONObject() }
        val entries = root.optJSONObject("entries") ?: JSONObject().also {
            root.put("entries", it)
        }
        val now = System.currentTimeMillis()
        snapshot.forEach { (key, url) ->
            entries.put(
                key,
                JSONObject().put("u", url).put("t", now)
            )
        }
        // Prune expired
        val toRemove = mutableListOf<String>()
        val keys = entries.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val item = entries.optJSONObject(key) ?: continue
            if (now - item.optLong("t", 0L) > DISK_TTL_MS) toRemove += key
        }
        toRemove.forEach { entries.remove(it) }
        // Cap size
        if (entries.length() > MAX_DISK) {
            val sorted = mutableListOf<Pair<String, Long>>()
            val k = entries.keys()
            while (k.hasNext()) {
                val key = k.next()
                sorted += key to (entries.optJSONObject(key)?.optLong("t") ?: 0L)
            }
            sorted.sortBy { it.second }
            sorted.take((entries.length() - MAX_DISK).coerceAtLeast(0)).forEach {
                entries.remove(it.first)
            }
        }
        diskFile.parentFile?.mkdirs()
        val tmp = File(diskFile.parentFile, "${diskFile.name}.tmp")
        tmp.writeText(root.toString(), Charsets.UTF_8)
        if (!tmp.renameTo(diskFile)) {
            tmp.copyTo(diskFile, overwrite = true)
            tmp.delete()
        }
    }

    private companion object {
        private const val TAG = "SongUrlCache"
        private const val MAX_MEMORY = 200
        private const val MAX_DISK = 400
        private const val DISK_TTL_MS = 7L * 24 * 60 * 60 * 1000
    }
}
