package com.music.player.data.common

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.Deferred

/**
 * 合并相同 key 的并发请求：同一时刻只执行一次 [block]，其余调用方共享同一结果。
 *
 * 关键点：真正的工作运行在一个独立的作用域里，而不是某个调用方的协程里。这样任何一个
 * 调用方（follower 或先发起的 leader）被取消时，只会取消它自己的 [await]，不会把
 * [CancellationException] 传染给共享同一结果的其他调用方，也不会取消底层的网络请求。
 */
class RequestCoalescer<K, V> {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val inFlight = mutableMapOf<K, Deferred<V>>()

    suspend fun run(key: K, block: suspend () -> V): V {
        val deferred = synchronized(this) {
            inFlight[key] ?: scope.async { block() }.also { started ->
                inFlight[key] = started
                started.invokeOnCompletion {
                    synchronized(this) {
                        if (inFlight[key] === started) {
                            inFlight.remove(key)
                        }
                    }
                }
            }
        }

        return deferred.await()
    }
}
