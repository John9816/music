package com.music.player.data.common

class TimedMemoryCache<K, V>(private val maxSize: Int = 100) {
    private data class Entry<V>(
        val value: V,
        val timestampMs: Long
    )

    private val store = LinkedHashMap<K, Entry<V>>(maxSize, 0.75f, true)

    @Synchronized
    fun get(key: K, ttlMs: Long, nowMs: Long = System.currentTimeMillis()): V? {
        val entry = store[key] ?: return null
        if (nowMs - entry.timestampMs > ttlMs) {
            store.remove(key)
            return null
        }
        return entry.value
    }

    /** Returns cached value even if TTL expired (does not remove the entry). */
    @Synchronized
    fun getStale(key: K): V? = store[key]?.value

    @Synchronized
    fun put(key: K, value: V, nowMs: Long = System.currentTimeMillis()) {
        // Evict oldest entries if at capacity (LinkedHashMap access-order keeps track of LRU)
        while (store.size >= maxSize) {
            val oldest = store.entries.iterator().next()
            store.remove(oldest.key)
        }
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
