package com.music.player.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.widget.RemoteViews
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.playback.PlaybackCoordinator
import com.music.player.playback.PlaybackService
import com.music.player.ui.util.ImageUrl
import java.util.concurrent.atomic.AtomicLong

@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
class PlayerAppWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE -> {
                PlaybackService.start(context)
                PlaybackCoordinator.togglePlayPause()
                refreshAll(context)
            }
            ACTION_NEXT -> {
                PlaybackService.start(context)
                PlaybackCoordinator.skipNext()
                refreshAll(context)
            }
            ACTION_PREV -> {
                PlaybackService.start(context)
                PlaybackCoordinator.skipPrevious()
                refreshAll(context)
            }
            ACTION_REFRESH -> refreshAll(context)
        }
    }

    companion object {
        const val ACTION_TOGGLE = "com.music.player.widget.TOGGLE"
        const val ACTION_NEXT = "com.music.player.widget.NEXT"
        const val ACTION_PREV = "com.music.player.widget.PREV"
        const val ACTION_REFRESH = "com.music.player.widget.REFRESH"

        private const val COVER_SIZE_PX = 144
        private const val COVER_CORNER_PX = 16f

        /** Bumps on each refresh so stale Glide callbacks are ignored. */
        private val coverLoadGeneration = AtomicLong(0L)

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PlayerAppWidget::class.java))
            if (ids.isEmpty()) return
            val generation = coverLoadGeneration.incrementAndGet()
            ids.forEach { updateWidget(context, manager, it, generation) }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            generation: Long = coverLoadGeneration.get()
        ) {
            val appContext = context.applicationContext
            val song = PlaybackCoordinator.currentSong.value
            val playing = PlaybackCoordinator.playerOrNull()?.isPlaying == true
            val views = buildBaseViews(appContext, song?.name, song?.artists, playing)
            views.setImageViewResource(R.id.ivWidgetCover, R.drawable.ic_music_note_24)
            manager.updateAppWidget(widgetId, views)

            val expectedSongId = song?.id
            val coverUrl = ImageUrl.thumbnail(song?.album?.picUrl, COVER_SIZE_PX)
            if (coverUrl.isNullOrBlank() || expectedSongId.isNullOrBlank()) return

            Glide.with(appContext)
                .asBitmap()
                .load(coverUrl)
                .override(COVER_SIZE_PX, COVER_SIZE_PX)
                .centerCrop()
                .into(object : CustomTarget<Bitmap>(COVER_SIZE_PX, COVER_SIZE_PX) {
                    override fun onResourceReady(
                        resource: Bitmap,
                        transition: Transition<in Bitmap>?
                    ) {
                        if (generation != coverLoadGeneration.get()) return
                        val current = PlaybackCoordinator.currentSong.value
                        if (current?.id != expectedSongId) return
                        val isPlaying = PlaybackCoordinator.playerOrNull()?.isPlaying == true
                        val rounded = roundCorners(resource, COVER_CORNER_PX)
                        val latest = buildBaseViews(
                            appContext,
                            current.name,
                            current.artists,
                            isPlaying
                        )
                        latest.setImageViewBitmap(R.id.ivWidgetCover, rounded)
                        manager.updateAppWidget(widgetId, latest)
                    }

                    override fun onLoadCleared(placeholder: Drawable?) = Unit
                })
        }

        private fun buildBaseViews(
            context: Context,
            title: String?,
            artists: List<com.music.player.data.model.Artist>?,
            playing: Boolean
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_player)
            views.setTextViewText(
                R.id.tvWidgetTitle,
                title ?: context.getString(R.string.widget_empty_title)
            )
            views.setTextViewText(
                R.id.tvWidgetArtist,
                artists?.joinToString(", ") { it.name }
                    ?.takeIf { it.isNotBlank() }
                    ?: context.getString(R.string.widget_empty_artist)
            )
            views.setImageViewResource(
                R.id.btnWidgetPlay,
                if (playing) R.drawable.ic_pause_24 else R.drawable.ic_play_24
            )

            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widgetRoot, open)
            views.setOnClickPendingIntent(
                R.id.btnWidgetPlay,
                broadcast(context, ACTION_TOGGLE, 1)
            )
            views.setOnClickPendingIntent(
                R.id.btnWidgetNext,
                broadcast(context, ACTION_NEXT, 2)
            )
            views.setOnClickPendingIntent(
                R.id.btnWidgetPrev,
                broadcast(context, ACTION_PREV, 3)
            )
            return views
        }

        private fun roundCorners(source: Bitmap, radiusPx: Float): Bitmap {
            val width = source.width.coerceAtLeast(1)
            val height = source.height.coerceAtLeast(1)
            val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
            canvas.drawRoundRect(rect, radiusPx, radiusPx, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(source, 0f, 0f, paint)
            return output
        }

        private fun broadcast(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, PlayerAppWidget::class.java).setAction(action)
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
    }
}
