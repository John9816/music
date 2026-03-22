package com.music.player.data.common

import kotlinx.coroutines.CompletableDeferred

class RequestCoalescer<K, V> {
    private val inFlight = mutableMapOf<K, CompletableDeferred<V>>()

    suspend fun run(key: K, block: suspend () -> V): V {
        val existing = synchronized(this) { inFlight[key] }
        if (existing != null) {
            return existing.await()
        }

        val deferred = CompletableDeferred<V>()
        val shouldExecute = synchronized(this) {
            val active = inFlight[key]
            if (active != null) {
                false
            } else {
                inFlight[key] = deferred
                true
            }
        }

        if (!shouldExecute) {
            return synchronized(this) { inFlight[key] }!!.await()
        }

        try {
            val result = block()
            deferred.complete(result)
            return result
        } catch (throwable: Throwable) {
            deferred.completeExceptionally(throwable)
            throw throwable
        } finally {
            synchronized(this) {
                if (inFlight[key] === deferred) {
                    inFlight.remove(key)
                }
            }
        }
    }
}
