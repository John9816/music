package com.music.player.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.TaskStackBuilder
import androidx.core.content.ContextCompat
import androidx.core.content.PermissionChecker
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerNotificationManager
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import com.music.player.MainActivity
import com.music.player.R

@UnstableApi
class PlaybackService : Service() {

    companion object {
        private const val TAG = "PlaybackService"
        private const val NOTIFICATION_ID = 1101
        private const val CHANNEL_ID = "playback"
        private const val CHANNEL_NAME = "音乐播放"

        fun intent(context: Context): Intent = Intent(context, PlaybackService::class.java)

        fun start(context: Context) {
            runCatching {
                val i = intent(context)
                if (Build.VERSION.SDK_INT >= 26) {
                    ContextCompat.startForegroundService(context, i)
                } else {
                    context.startService(i)
                }
            }
        }
    }

    private lateinit var player: ExoPlayer
    private lateinit var notificationPlayer: QueueAwarePlayer
    private lateinit var notificationManager: PlayerNotificationManager
    private var lastStateChangeElapsedMs: Long = 0L

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForegroundPlaceholder()

        val loadControl = DefaultLoadControl.Builder()
            // Start faster (less initial buffering) while keeping a reasonable steady-state buffer.
            .setBufferDurationsMs(
                /* minBufferMs = */ 6_000,
                /* maxBufferMs = */ 30_000,
                /* bufferForPlaybackMs = */ 800,
                /* bufferForPlaybackAfterRebufferMs = */ 1_800
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val httpFactory = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(10_000)
            .setReadTimeoutMs(15_000)
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent("MusicPlayer/1.0 (Android)")

        val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        player = ExoPlayer.Builder(this)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
        PlaybackCoordinator.attachPlayer(this, player)
        notificationPlayer = QueueAwarePlayer(player)

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                val now = SystemClock.elapsedRealtime()
                val delta = if (lastStateChangeElapsedMs == 0L) 0L else now - lastStateChangeElapsedMs
                lastStateChangeElapsedMs = now
                val stateName = when (playbackState) {
                    Player.STATE_IDLE -> "IDLE"
                    Player.STATE_BUFFERING -> "BUFFERING"
                    Player.STATE_READY -> "READY"
                    Player.STATE_ENDED -> "ENDED"
                    else -> playbackState.toString()
                }
                Log.d(TAG, "player state=$stateName (+${delta}ms)")
                if (playbackState == Player.STATE_ENDED) {
                    PlaybackCoordinator.onPlaybackEndedAutoAdvance()
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                Log.e(TAG, "player error: ${error.errorCodeName}: ${error.message}", error)
            }
        })

        notificationManager = PlayerNotificationManager.Builder(this, NOTIFICATION_ID, CHANNEL_ID)
            .setMediaDescriptionAdapter(descriptionAdapter)
            .setNotificationListener(notificationListener)
            .setSmallIconResourceId(R.drawable.ic_music_note_24)
            .build()

        notificationManager.setPlayer(notificationPlayer)
        notificationManager.setUseChronometer(false)
        notificationManager.setUseNextAction(true)
        notificationManager.setUsePreviousAction(true)
        notificationManager.setUseNextActionInCompactView(true)
        notificationManager.setUsePreviousActionInCompactView(true)

        notificationManager.setUseFastForwardAction(false)
        notificationManager.setUseRewindAction(false)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        notificationManager.setPlayer(null)
        player.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private val descriptionAdapter = object : PlayerNotificationManager.MediaDescriptionAdapter {
        override fun getCurrentContentTitle(player: Player): CharSequence {
            return player.mediaMetadata.title ?: getString(R.string.app_name)
        }

        override fun createCurrentContentIntent(player: Player) =
            TaskStackBuilder.create(this@PlaybackService)
                .addNextIntentWithParentStack(Intent(this@PlaybackService, MainActivity::class.java))
                .getPendingIntent(
                    0,
                    (if (Build.VERSION.SDK_INT >= 23) android.app.PendingIntent.FLAG_IMMUTABLE else 0) or
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT
                )

        override fun getCurrentContentText(player: Player): CharSequence? {
            return player.mediaMetadata.artist
        }

        override fun getCurrentLargeIcon(
            player: Player,
            callback: PlayerNotificationManager.BitmapCallback
        ): Bitmap? {
            val uri = player.mediaMetadata.artworkUri ?: return null
            Glide.with(this@PlaybackService)
                .asBitmap()
                .load(uri)
                .into(object : CustomTarget<Bitmap>(240, 240) {
                    override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                        callback.onBitmap(resource)
                    }

                    override fun onLoadCleared(placeholder: android.graphics.drawable.Drawable?) = Unit
                })
            return null
        }
    }

    private val notificationListener = object : PlayerNotificationManager.NotificationListener {
        override fun onNotificationPosted(
            notificationId: Int,
            notification: Notification,
            ongoing: Boolean
        ) {
            if (ongoing) {
                runCatching {
                    if (canPostNotifications()) {
                        startForeground(notificationId, notification)
                    } else {
                        Log.w(TAG, "notifications disabled; skip startForeground()")
                    }
                }.onFailure { t ->
                    Log.e(TAG, "startForeground failed", t)
                }
            } else {
                runCatching { stopForeground(STOP_FOREGROUND_DETACH) }
            }
        }

        override fun onNotificationCancelled(notificationId: Int, dismissedByUser: Boolean) {
            runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
            PlaybackCoordinator.resetPlayback()
            stopSelf()
        }
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return PermissionChecker.checkSelfPermission(
            this,
            android.Manifest.permission.POST_NOTIFICATIONS
        ) == PermissionChecker.PERMISSION_GRANTED
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = CHANNEL_NAME
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun startForegroundPlaceholder() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_music_note_24)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.app_name))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        runCatching { startForeground(NOTIFICATION_ID, notification) }
    }
}
