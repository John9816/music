package com.music.player.data.auth

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object SupabaseClient {
    private const val SUPABASE_URL = "https://vtvzpdupygvtytunrpdw.supabase.co"

    // 从 daohangv2 项目获取的真实 anon key
    private const val SUPABASE_ANON_KEY = "sb_publishable_DWdy6_bOXKnHO5aKG7cM0A__mo-PjT8"

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = if (com.music.player.BuildConfig.DEBUG) {
            HttpLoggingInterceptor.Level.BODY
        } else {
            HttpLoggingInterceptor.Level.BASIC
        }
    }

    private val okHttpClient = OkHttpClient.Builder()
        .addInterceptor(loggingInterceptor)
        .addInterceptor { chain ->
            val originalRequest = chain.request()
            val request = originalRequest.newBuilder()
                .addHeader("apikey", SUPABASE_ANON_KEY)
                .addHeader("Content-Type", "application/json")
                .build()

            if (com.music.player.BuildConfig.DEBUG) {
                Log.d("SupabaseClient", "Request URL: ${request.url}")
            }

            chain.proceed(request)
        }
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    val retrofit: Retrofit = Retrofit.Builder()
        .baseUrl("$SUPABASE_URL/")
        .client(okHttpClient)
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    val authApi: SupabaseAuthApi = retrofit.create(SupabaseAuthApi::class.java)
    val restApi: SupabaseRestApi = retrofit.create(SupabaseRestApi::class.java)
    val musicApi: SupabaseMusicApi = retrofit.create(SupabaseMusicApi::class.java)
}
