package com.music.player.playback

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.DefaultMediaNotificationProvider
import com.music.player.R
import com.music.player.MainActivity

/**
 * 基于 Media3 的媒体会话服务。通知、前台服务、锁屏控制、蓝牙/有线耳机媒体按键、
 * Android Auto 与系统媒体面板全部由 [MediaSessionService] + [MediaSession] 托管，
 * 无需再手动维护 PlayerNotificationManager 与 startForeground。
 */
@UnstableApi
class PlaybackService : MediaSessionService() {

    companion object {
        private const val TAG = "PlaybackService"

        fun intent(context: Context): Intent = Intent(context, PlaybackService::class.java)

        fun start(context: Context) {
            // 注意：MediaSessionService 仅在真正开始播放时才会自行进入前台并发通知。
            // 因此这里必须用普通 startService 而非 startForegroundService——否则会向系统
            // 承诺 5 秒内 startForeground，而启动时并无播放内容，导致
            // ForegroundServiceDidNotStartInTimeException 崩溃。
            // init() 在 MainActivity.onCreate（应用处于前台）调用，普通 startService 不受后台启动限制。
            runCatching {
                context.startService(intent(context))
            }
        }
    }

    private lateinit var player: ExoPlayer
    private lateinit var notificationPlayer: QueueAwarePlayer
    private var mediaSession: MediaSession? = null
    private var lastStateChangeElapsedMs: Long = 0L

    override fun onCreate() {
        super.onCreate()
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider(this).apply {
                setSmallIcon(R.drawable.ic_music_note_24)
            }
        )

        val loadControl = DefaultLoadControl.Builder()
            // Prefer stable audio over the fastest possible start. Short buffers caused
            // repeated rebuffering on unstable music URLs.
            .setBufferDurationsMs(
                /* minBufferMs = */ 20_000,
                /* maxBufferMs = */ 90_000,
                /* bufferForPlaybackMs = */ 2_500,
                /* bufferForPlaybackAfterRebufferMs = */ 8_000
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

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        player = ExoPlayer.Builder(this)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setAudioAttributes(audioAttributes, /* handleAudioFocus = */ true)
            .setHandleAudioBecomingNoisy(true)
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
                Log.d(
                    TAG,
                    "player state=$stateName (+${delta}ms), " +
                        "position=${player.currentPosition}, " +
                        "buffered=${player.bufferedPosition}, " +
                        "totalBuffered=${player.totalBufferedDuration}, " +
                        "duration=${player.duration}, " +
                        "playWhenReady=${player.playWhenReady}"
                )
                if (playbackState == Player.STATE_ENDED) {
                    val durationMs = player.duration
                    val positionMs = player.currentPosition.coerceAtLeast(0L)
                    val looksUnexpectedEnd =
                        durationMs != C.TIME_UNSET &&
                            durationMs > 0L &&
                            positionMs in 10_000L until (durationMs - 5_000L)

                    if (looksUnexpectedEnd) {
                        Log.w(TAG, "unexpected ended at ${positionMs}ms / ${durationMs}ms, trying to recover")
                        PlaybackCoordinator.recoverCurrentPlayback(
                            resumePositionMs = positionMs,
                            reason = "播放中断，正在继续"
                        )
                    } else {
                        PlaybackCoordinator.onPlaybackEndedAutoAdvance()
                    }
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                Log.e(TAG, "player error: ${error.errorCodeName}: ${error.message}", error)
                PlaybackCoordinator.recoverCurrentPlayback(
                    resumePositionMs = player.currentPosition.coerceAtLeast(0L),
                    reason = "播放异常，正在重连"
                )
            }
        })

        mediaSession = MediaSession.Builder(this, notificationPlayer)
            .setSessionActivity(buildContentIntent())
            .build()

        // Register the session with MediaSessionService so its notification manager receives
        // playback callbacks even before an external MediaController connects.
        addSession(checkNotNull(mediaSession))
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 用户从最近任务划掉应用时，若未在播放则停止服务，避免残留通知。
        val p = mediaSession?.player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        mediaSession?.run {
            release()
        }
        mediaSession = null
        if (::player.isInitialized) {
            PlaybackCoordinator.detachPlayer(player)
            player.release()
        }
        super.onDestroy()
    }

    private fun buildContentIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        return PendingIntent.getActivity(this, 0, intent, flags)
    }
}
