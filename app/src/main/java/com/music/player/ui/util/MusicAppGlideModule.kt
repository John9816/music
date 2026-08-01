package com.music.player.ui.util

import android.content.Context
import android.util.Log
import androidx.annotation.Keep
import com.bumptech.glide.Glide
import com.bumptech.glide.GlideBuilder
import com.bumptech.glide.Registry
import com.bumptech.glide.annotation.GlideModule
import com.bumptech.glide.integration.okhttp3.OkHttpUrlLoader
import com.bumptech.glide.load.engine.cache.InternalCacheDiskCacheFactory
import com.bumptech.glide.load.engine.cache.MemorySizeCalculator
import com.bumptech.glide.load.model.GlideUrl
import com.bumptech.glide.module.AppGlideModule
import com.bumptech.glide.request.RequestOptions
import com.music.player.data.api.NetworkRuntime
import okhttp3.OkHttpClient
import java.io.InputStream
import java.util.concurrent.TimeUnit

/**
 * Global Glide configuration:
 * - Shares the OkHttp connection pool with the rest of the app so album-art TCP/TLS
 *   connections are reused across API and image requests (no separate connection pool).
 * - Adds a 5-second per-image timeout so a slow CDN doesn't tie up a Glide thread.
 * - Sets a dedicated 50 MB disk cache under the app's cache dir.
 * - Applies default RequestOptions (dontAnimate + centerCrop) so every adapter call
 *   inherits sensible defaults without repeating them.
 */
@GlideModule
@Keep
class MusicAppGlideModule : AppGlideModule() {

    private val imageHttpClient by lazy {
        OkHttpClient.Builder()
            .connectionPool(NetworkRuntime.connectionPool())
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(7, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    override fun applyOptions(context: Context, builder: GlideBuilder) {
        val calculator = MemorySizeCalculator.Builder(context)
            .setMemoryCacheScreens(2f)
            .setBitmapPoolScreens(3f)
            .build()

        builder
            .setMemorySizeCalculator(calculator)
            .setDiskCache(InternalCacheDiskCacheFactory(context, 50L * 1024 * 1024))
            .setDefaultRequestOptions(
                RequestOptions()
                    .dontAnimate()
                    .centerCrop()
            )
    }

    override fun registerComponents(context: Context, glide: Glide, registry: Registry) {
        registry.replace(
            GlideUrl::class.java,
            InputStream::class.java,
            OkHttpUrlLoader.Factory(imageHttpClient)
        )
    }

    override fun isManifestParsingEnabled(): Boolean = false
}
