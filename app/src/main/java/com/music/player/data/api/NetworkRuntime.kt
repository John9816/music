package com.music.player.data.api

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import okhttp3.Cache
import okhttp3.ConnectionPool
import java.io.File
import java.util.concurrent.TimeUnit

object NetworkRuntime {
    @Volatile
    private var appContext: Context? = null

    private val connectionPool by lazy {
        ConnectionPool(8, 5, TimeUnit.MINUTES)
    }

    fun init(context: Context) {
        if (appContext == null) {
            synchronized(this) {
                if (appContext == null) {
                    appContext = context.applicationContext
                }
            }
        }
    }

    fun connectionPool(): ConnectionPool = connectionPool

    fun applicationContext(): Context {
        return requireNotNull(appContext) { "NetworkRuntime is not initialized" }
    }

    fun applicationContextOrNull(): Context? = appContext

    fun httpCache(directoryName: String, maxSizeBytes: Long): Cache {
        val context = applicationContext()
        val directory = File(context.cacheDir, directoryName).apply { mkdirs() }
        return Cache(directory, maxSizeBytes)
    }

    fun isNetworkAvailable(): Boolean {
        val context = appContext ?: return true
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return true
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            return false
        }

        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)
    }
}
