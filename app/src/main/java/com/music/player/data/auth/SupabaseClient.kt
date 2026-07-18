package com.music.player.data.auth

import android.util.Log
import com.music.player.data.api.NetworkRuntime
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object SupabaseClient {
    // Sourced from BuildConfig (local.properties / CI env), never hardcoded here.
    val SUPABASE_URL: String = com.music.player.BuildConfig.SUPABASE_URL
    const val AVATAR_BUCKET = "avatars"

    private val SUPABASE_ANON_KEY: String = com.music.player.BuildConfig.SUPABASE_ANON_KEY

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = if (com.music.player.BuildConfig.DEBUG) {
            HttpLoggingInterceptor.Level.BASIC
        } else {
            HttpLoggingInterceptor.Level.NONE
        }
        // Guard: if the level is ever raised to HEADERS/BODY for debugging, keep secrets out of logs.
        redactHeader("Authorization")
        redactHeader("apikey")
    }

    private val okHttpClient = OkHttpClient.Builder()
        .connectionPool(NetworkRuntime.connectionPool())
        .retryOnConnectionFailure(true)
        .addInterceptor(loggingInterceptor)
        .addInterceptor { chain ->
            val originalRequest = chain.request()
            val requestBuilder = originalRequest.newBuilder()
                .addHeader("apikey", SUPABASE_ANON_KEY)
            if (originalRequest.header("Content-Type").isNullOrBlank()) {
                requestBuilder.addHeader("Content-Type", "application/json")
            }
            val request = requestBuilder.build()
            chain.proceed(request)
        }
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .build()

    val retrofit: Retrofit = Retrofit.Builder()
        .baseUrl("$SUPABASE_URL/")
        .client(okHttpClient)
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    val authApi: SupabaseAuthApi = retrofit.create(SupabaseAuthApi::class.java)
    val musicApi: SupabaseMusicApi = retrofit.create(SupabaseMusicApi::class.java)
}
