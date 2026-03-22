package com.music.player.data.auth

import android.util.Log
import com.music.player.data.api.NetworkRuntime
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
            HttpLoggingInterceptor.Level.NONE
        }
    }

    private val okHttpClient = OkHttpClient.Builder()
        .connectionPool(NetworkRuntime.connectionPool())
        .retryOnConnectionFailure(true)
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
    val restApi: SupabaseRestApi = retrofit.create(SupabaseRestApi::class.java)
    val musicApi: SupabaseMusicApi = retrofit.create(SupabaseMusicApi::class.java)
}
