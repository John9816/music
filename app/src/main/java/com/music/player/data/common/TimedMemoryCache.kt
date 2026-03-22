package com.music.player.data.common

class TimedMemoryCache<K, V> {
    private data class Entry<V>(
        val value: V,
        val timestampMs: Long
    )

    private val store = LinkedHashMap<K, Entry<V>>()

    @Synchronized
    fun get(key: K, ttlMs: Long, nowMs: Long = System.currentTimeMillis()): V? {
        val entry = store[key] ?: return null
        if (nowMs - entry.timestampMs > ttlMs) {
            store.remove(key)
            return null
        }
        return entry.value
    }

    @Synchronized
    fun put(key: K, value: V, nowMs: Long = System.currentTimeMillis()) {
        store[key] = Entry(value = value, timestampMs = nowMs)
    }

    @Synchronized
    fun remove(key: K) {
        store.remove(key)
    }

    @Synchronized
    fun clear() {
        store.clear()
    }
}
