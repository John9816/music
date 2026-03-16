package com.music.player.data.api

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
    private const val ALGER_BASE_URL = "http://mc.alger.fun/"
    private const val GDSTUDIO_BASE_URL = "https://music-api.gdstudio.xyz/"
    private const val LYRICS_BASE_URL = "https://node.api.xfabe.com/"

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.BASIC
    }

    private val algerHeadersInterceptor = Interceptor { chain ->
        val request = chain.request()
        if (request.url.host == "mc.alger.fun") {
            val updated = request.newBuilder()
                .header("Accept", "application/json, text/plain, */*")
                .header("Accept-Language", "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7")
                .header("Referer", "http://mc.alger.fun/")
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

    private val okHttpClient = OkHttpClient.Builder()
        .cookieJar(InMemoryCookieJar())
        .addInterceptor(algerHeadersInterceptor)
        .addInterceptor(loggingInterceptor)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private fun createRetrofit(baseUrl: String): Retrofit {
        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    val musicApi: MusicApiService = createRetrofit(ALGER_BASE_URL).create(MusicApiService::class.java)
    val gdStudioApi: GdStudioApiService = createRetrofit(GDSTUDIO_BASE_URL).create(GdStudioApiService::class.java)
    val lyricsApi: LyricsApiService = createRetrofit(LYRICS_BASE_URL).create(LyricsApiService::class.java)
}

private class InMemoryCookieJar : CookieJar {
    private val store = mutableMapOf<String, MutableList<Cookie>>()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
        val host = url.host
        val existing = store.getOrPut(host) { mutableListOf() }
        val now = System.currentTimeMillis()
        val incoming = cookies.filter { it.expiresAt >= now }
        incoming.forEach { cookie ->
            existing.removeAll { it.name == cookie.name && it.domain == cookie.domain && it.path == cookie.path }
            existing.add(cookie)
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val host = url.host
        val now = System.currentTimeMillis()
        val cookies = store[host].orEmpty()
            .filter { it.expiresAt >= now && it.matches(url) }
        store[host] = cookies.toMutableList()
        return cookies
    }
}
