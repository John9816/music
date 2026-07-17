package com.music.player.data.api

import com.music.player.BuildConfig
import okhttp3.CacheControl
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Interceptor
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object RetrofitClient {
    private const val MUSIC_BASE_URL = "https://api.751152.xyz/"
    private const val HTTP_CACHE_SIZE_BYTES = 32L * 1024L * 1024L
    private val connectionPool: ConnectionPool = NetworkRuntime.connectionPool()

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = if (BuildConfig.DEBUG) {
            HttpLoggingInterceptor.Level.BASIC
        } else {
            HttpLoggingInterceptor.Level.NONE
        }
        // Guard: keep secrets out of logs if the level is ever raised for debugging.
        redactHeader("Authorization")
        redactHeader("apikey")
    }

    private val algerHeadersInterceptor = Interceptor { chain ->
        val request = chain.request()
        if (request.url.host == "api.751152.xyz") {
            val updated = request.newBuilder()
                .header("Accept", "application/json, text/plain, */*")
                .header("Accept-Language", "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7")
                .header("Referer", MUSIC_BASE_URL)
                .header(
                    "User-Agent",
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
                )
                .build()
            chain.proceed(updated)
        } else {
            chain.proceed(request)
        }
    }

    private val offlineCacheInterceptor = Interceptor { chain ->
        var request = chain.request()
        if (request.method.equals("GET", ignoreCase = true) && !NetworkRuntime.isNetworkAvailable()) {
            request = request.newBuilder()
                .cacheControl(
                    CacheControl.Builder()
                        .onlyIfCached()
                        .maxStale(7, TimeUnit.DAYS)
                        .build()
                )
                .build()
        }
        chain.proceed(request)
    }

    private val responseCacheInterceptor = Interceptor { chain ->
        val request = chain.request()
        val response = chain.proceed(request)
        if (!request.method.equals("GET", ignoreCase = true)) {
            return@Interceptor response
        }
        if (request.header("Cache-Control") != null || response.header("Cache-Control") != null) {
            return@Interceptor response
        }

        val maxAgeSeconds = when (request.url.encodedPath) {
            "/api/v1/music/lyric" -> 7 * 24 * 60 * 60
            "/api/v1/music/play" -> 20 * 60
            "/api/v1/music/playlist/detail" -> 10 * 60
            "/api/v1/music/playlist" -> 10 * 60
            "/api/v1/music/new" -> 5 * 60
            "/api/v1/music/toplist" -> 10 * 60
            "/api/v1/music/toplist/detail" -> 10 * 60
            else -> 5 * 60
        }

        response.newBuilder()
            .removeHeader("Pragma")
            .header("Cache-Control", "public, max-age=$maxAgeSeconds")
            .build()
    }

    private val okHttpClient = OkHttpClient.Builder()
        .cache(NetworkRuntime.httpCache(directoryName = "music-http-cache", maxSizeBytes = HTTP_CACHE_SIZE_BYTES))
        .connectionPool(connectionPool)
        .retryOnConnectionFailure(true)
        .cookieJar(InMemoryCookieJar())
        .addInterceptor(offlineCacheInterceptor)
        .addInterceptor(algerHeadersInterceptor)
        .addNetworkInterceptor(responseCacheInterceptor)
        .addInterceptor(loggingInterceptor)
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .build()

    private fun createRetrofit(baseUrl: String): Retrofit {
        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    val musicApi: MusicApiService = createRetrofit(MUSIC_BASE_URL).create(MusicApiService::class.java)
}

private class InMemoryCookieJar : CookieJar {
    private val store = mutableMapOf<String, MutableList<Cookie>>()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
        val host = url.host
        val now = System.currentTimeMillis()
        val incoming = cookies.filter { it.expiresAt >= now }
        if (incoming.isEmpty()) return
        synchronized(this) {
            val existing = store.getOrPut(host) { mutableListOf() }
            incoming.forEach { cookie ->
                existing.removeAll { it.name == cookie.name && it.domain == cookie.domain && it.path == cookie.path }
                existing.add(cookie)
            }
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val host = url.host
        val now = System.currentTimeMillis()
        return synchronized(this) {
            val cookies = store[host].orEmpty()
                .filter { it.expiresAt >= now && it.matches(url) }
            if (cookies.isEmpty()) {
                store.remove(host)
            } else {
                store[host] = cookies.toMutableList()
            }
            cookies
        }
    }
}
