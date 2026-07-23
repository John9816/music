package com.music.player.ui.fragment

import android.content.Intent
import android.content.res.ColorStateList
import android.os.Bundle
import android.os.Build
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import androidx.core.graphics.ColorUtils
import android.util.TypedValue
import android.view.GestureDetector
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.WindowCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.doOnLayout
import androidx.core.view.isVisible
import androidx.core.view.updatePadding
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.FragmentManager
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.resource.drawable.DrawableTransitionOptions
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.data.model.LyricLine
import com.music.player.databinding.BottomSheetNowPlayingBinding
import com.music.player.ui.adapter.LyricsAdapter
import com.music.player.ui.util.ImmersiveHeaderBackground
import com.music.player.ui.lyrics.LyricsParser
import com.music.player.ui.util.PlayerUiStyler
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.installDownwardDragToDismiss
import com.music.player.playback.PlaybackCoordinator
import com.music.player.playback.PlaybackMode
import com.music.player.playback.PlaybackModeController
import com.music.player.ui.viewmodel.MusicViewModel
import androidx.media3.common.Player
import androidx.media3.common.C
import com.google.android.material.slider.Slider
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.data.settings.AudioQualityPreferences
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.music.player.ui.viewmodel.LibraryViewModel
import java.util.Locale

class NowPlayingBottomSheetFragment : DialogFragment() {

    companion object {
        const val TAG = "now_playing"
        private const val STAGE_ANIMATION_MS = 240L
        private const val COVER_PULSE_DURATION_MS = 3600L
        private const val HANDLE_DISMISS_DISTANCE_DP = 80f
        private const val COVER_CROSSFADE_MS = 220

        /**
         * Show at most one full player. [DialogFragment.show] only does async [FragmentTransaction.add];
         * two quick taps create two instances with the same tag before the first commit lands.
         */
        fun showIfAbsent(fragmentManager: FragmentManager) {
            if (fragmentManager.isStateSaved) return
            if (isShowing(fragmentManager)) return
            runCatching { fragmentManager.executePendingTransactions() }
            if (isShowing(fragmentManager)) return
            NowPlayingBottomSheetFragment().show(fragmentManager, TAG)
        }

        fun isShowing(fragmentManager: FragmentManager): Boolean {
            val existing = fragmentManager.findFragmentByTag(TAG) ?: return false
            if (!existing.isAdded && existing.isRemoving) return false
            if (existing is DialogFragment) {
                val dialog = existing.dialog
                if (dialog != null && dialog.isShowing) return true
                // Added but dialog not created yet (between show() and onStart).
                if (existing.isAdded && !existing.isRemoving) return true
            }
            return existing.isAdded && !existing.isRemoving
        }
    }

    private var _binding: BottomSheetNowPlayingBinding? = null
    private val binding: BottomSheetNowPlayingBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var lyricsAdapter: LyricsAdapter

    // Direct references to player content views (no ViewPager2)
    private var coverStage: View? = null
    private var lyricsStage: View? = null
    private var discContainer: View? = null
    private var ivCoverBig: ImageView? = null
    private var rvLyrics: RecyclerView? = null
    private var tvLyricsPlain: TextView? = null
    private var contentPaddingStart: Int = 0
    private var contentPaddingTop: Int = 0
    private var contentPaddingEnd: Int = 0
    private var contentPaddingBottom: Int = 0

    private var lyricLines: List<LyricLine> = emptyList()
    private var lyricJob: Job? = null
    private var lyricParseJob: Job? = null
    private var lyricRenderToken = 0L
    private var progressJob: Job? = null
    private var currentActiveIndex: Int = -1
    private var isUserScrollingLyrics = false
    private var isUserSeeking: Boolean = false
    private var coverRotateAnimator: ObjectAnimator? = null
    private var favoriteIds: Set<String> = emptySet()
    private var showingLyrics: Boolean = false
    private var viewGlowHalo: View? = null
    private var glowAnimator: ObjectAnimator? = null
    private var immersiveBackground: ImmersiveHeaderBackground? = null

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            syncPlayPauseIcon(isPlaying)
        }

        override fun onRepeatModeChanged(repeatMode: Int) {
            syncPlayModeIcon()
        }

        override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
            syncPlayModeIcon()
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = BottomSheetNowPlayingBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun getTheme(): Int = R.style.ThemeOverlayMusicPlayerFullscreenDialog

    @Suppress("DEPRECATION")
    override fun onStart() {
        super.onStart()

        (activity as? MainActivity)?.animatePlayerBackground(expanded = true)

        dialog?.window?.let { window ->
            WindowCompat.setDecorFitsSystemWindows(window, false)
            window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            window.setLayout(MATCH_PARENT, MATCH_PARENT)
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            window.attributes = window.attributes.apply {
                width = MATCH_PARENT
                height = MATCH_PARENT
                if (Build.VERSION.SDK_INT >= 28) {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
                if (Build.VERSION.SDK_INT >= 31) {
                    dimAmount = 0.06f
                }
            }
            if (Build.VERSION.SDK_INT >= 29) {
                window.isStatusBarContrastEnforced = false
                window.isNavigationBarContrastEnforced = false
            }
            val controller = WindowInsetsControllerCompat(window, binding.root)
            // Full player is always dark chrome over album blur — light icons in system bars.
            controller.isAppearanceLightStatusBars = false
            controller.isAppearanceLightNavigationBars = false
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.show(WindowInsetsCompat.Type.systemBars())
        }

        startLyricUpdates()
        startProgressUpdates()
    }

    override fun onStop() {
        lyricJob?.cancel()
        lyricJob = null
        lyricParseJob?.cancel()
        lyricParseJob = null
        progressJob?.cancel()
        progressJob = null
        stopCoverRotation()
        stopGlowAnimation()
        (activity as? MainActivity)?.animatePlayerBackground(expanded = false)
        super.onStop()
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        lyricsAdapter = LyricsAdapter()
        PlayerUiStyler.applyNowPlaying(binding, requireContext())
        binding.topBar.applyStatusBarInsetPadding()
        binding.controlsBar.applyNavigationBarInsetPadding()
        // Album-art blur under a dark scrim (NetEase-style immersive player).
        binding.ivBlurBackground.visibility = View.VISIBLE
        immersiveBackground = ImmersiveHeaderBackground(
            lifecycleOwner = viewLifecycleOwner,
            imageView = binding.ivBlurBackground
        ) { binding.viewScrim.alpha = 1f }

        // Direct view references — no ViewPager2
        // playerContent is an included layout binding (PageNowPlayingCoverBinding)
        val contentRoot = binding.playerContent.root
        contentPaddingStart = contentRoot.paddingLeft
        contentPaddingTop = contentRoot.paddingTop
        contentPaddingEnd = contentRoot.paddingRight
        contentPaddingBottom = contentRoot.paddingBottom
        coverStage = contentRoot.findViewById(R.id.coverStage)
        lyricsStage = contentRoot.findViewById(R.id.lyricsStage)
        discContainer = contentRoot.findViewById(R.id.discContainer)
        ivCoverBig = contentRoot.findViewById(R.id.ivCoverBig)
        rvLyrics = contentRoot.findViewById(R.id.rvLyrics)
        tvLyricsPlain = contentRoot.findViewById(R.id.tvLyricsPlain)
        viewGlowHalo = contentRoot.findViewById(R.id.viewGlowHalo)

        coverStage?.setOnClickListener { showLyricsStage() }
        lyricsStage?.setOnClickListener { showCoverStage() }
        showCoverStage(immediate = true)

        // Setup lyrics RecyclerView
        rvLyrics?.layoutManager = LinearLayoutManager(requireContext())
        rvLyrics?.adapter = lyricsAdapter
        rvLyrics?.itemAnimator = null
        rvLyrics?.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                isUserScrollingLyrics = newState == RecyclerView.SCROLL_STATE_DRAGGING
                if (newState == RecyclerView.SCROLL_STATE_IDLE && showingLyrics) {
                    syncActiveLyric(scroll = true)
                }
            }
        })
        rvLyrics?.addOnItemTouchListener(object : RecyclerView.SimpleOnItemTouchListener() {
            private val tapDetector = GestureDetector(
                requireContext(),
                object : GestureDetector.SimpleOnGestureListener() {
                    override fun onSingleTapUp(e: MotionEvent): Boolean = true
                }
            )

            override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                if (tapDetector.onTouchEvent(e)) {
                    showCoverStage()
                    return true
                }
                return false
            }
        })
        rvLyrics?.doOnLayout { rv ->
            val minInset = dp(24)
            val inset = (rv.height / 2 - minInset).coerceAtLeast(minInset)
            (rv as? RecyclerView)?.setPadding(
                rv.paddingLeft, inset, rv.paddingRight, inset
            )
        }

        binding.root.doOnLayout { updateFullscreenContentPadding() }
        binding.topBar.doOnLayout { updateFullscreenContentPadding() }
        binding.progressContainer.doOnLayout { updateFullscreenContentPadding() }
        binding.controlsBar.doOnLayout { updateFullscreenContentPadding() }

        binding.btnClose.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnAudioQuality.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnOverflow.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnQueue.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnFavorite.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnPrev.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnNext.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnPlayPause.bindPressFeedback(PressFeedback.Style.PLAY)
        binding.btnPlayMode.bindPressFeedback(PressFeedback.Style.ICON)
        listOf(
            binding.menuShowLyrics,
            binding.menuFavoriteSong,
            binding.menuShareSong,
            binding.menuDownloadSong,
            binding.menuAddPlaylist,
            binding.menuShowAlbum
        ).forEach { it.bindPressFeedback(PressFeedback.Style.ROW) }

        binding.btnClose.setOnClickListener {
            (activity as? MainActivity)?.animatePlayerBackground(expanded = false)
            dismiss()
        }
        installHandleDragToDismiss()
        binding.btnAudioQuality.setOnClickListener { showAudioQualityDialog() }
        binding.btnOverflow.setOnClickListener {
            binding.layoutSongMenu.isVisible = !binding.layoutSongMenu.isVisible
        }
        binding.menuShowLyrics.setOnClickListener {
            binding.layoutSongMenu.isVisible = false
            showLyricsStage()
        }
        binding.menuFavoriteSong.setOnClickListener {
            binding.layoutSongMenu.isVisible = false
            toggleFavoriteForCurrentSong()
        }
        binding.menuShareSong.setOnClickListener {
            binding.layoutSongMenu.isVisible = false
            musicViewModel.currentSong.value?.let(::shareCurrentSong)
        }
        binding.menuDownloadSong.setOnClickListener {
            binding.layoutSongMenu.isVisible = false
            musicViewModel.currentSong.value?.let { song ->
                SongDownloader.download(requireContext(), musicViewModel, song)
            }
        }
        binding.menuAddPlaylist.setOnClickListener {
            binding.layoutSongMenu.isVisible = false
            musicViewModel.currentSong.value?.let(::showAddToPlaylistDialog)
        }
        binding.menuShowAlbum.setOnClickListener {
            binding.layoutSongMenu.isVisible = false
            musicViewModel.currentSong.value?.let(::openCurrentAlbum)
        }
        binding.btnQueue.setOnClickListener {
            QueueBottomSheetFragment().show(parentFragmentManager, "queue")
        }
        binding.btnFavorite.setOnClickListener { toggleFavoriteForCurrentSong() }
        updateAudioQualityButton()
        updateFavoriteButton()

        val player = (activity as? MainActivity)?.player
        if (player != null) {
            player.addListener(playerListener)
            syncPlayPauseIcon(player.isPlaying)
            syncPlayModeIcon()
        }

        binding.sliderProgress.addOnSliderTouchListener(object : Slider.OnSliderTouchListener {
            override fun onStartTrackingTouch(slider: Slider) {
                isUserSeeking = true
            }

            override fun onStopTrackingTouch(slider: Slider) {
                val p = (activity as? MainActivity)?.player
                if (p != null) {
                    p.seekTo(slider.value.toLong().coerceAtLeast(0L))
                }
                isUserSeeking = false
            }
        })

        binding.sliderProgress.addOnChangeListener { _, value, fromUser ->
            if (fromUser) {
                binding.tvCurrentTime.text = formatTime(value.toLong())
            }
        }

        binding.btnPrev.setOnClickListener {
            musicViewModel.skipPrevious()
        }
        binding.btnNext.setOnClickListener {
            musicViewModel.skipNext()
        }
        binding.btnPlayPause.setOnClickListener {
            val p = (activity as? MainActivity)?.player ?: return@setOnClickListener
            val currentSong = musicViewModel.currentSong.value
            if (p.isPlaying) {
                p.pause()
            } else if (p.mediaItemCount == 0 && currentSong != null) {
                musicViewModel.playSong(currentSong)
            } else {
                if (p.playbackState == Player.STATE_IDLE && p.mediaItemCount > 0) {
                    p.prepare()
                }
                p.play()
            }
            syncPlayPauseIcon(p.isPlaying)
        }

        binding.btnPlayMode.setOnClickListener {
            val p = (activity as? MainActivity)?.player ?: return@setOnClickListener
            val next = PlaybackModeController.next(PlaybackModeController.resolve(p))
            PlaybackModeController.apply(p, next)
            syncPlayModeIcon()
        }

        musicViewModel.queue.observe(viewLifecycleOwner) {
            syncSkipButtons()
            updatePlaybackMeta()
        }
        musicViewModel.canSkipPrevious.observe(viewLifecycleOwner) {
            syncSkipButtons()
        }
        libraryViewModel.favoriteIds.observe(viewLifecycleOwner) { ids ->
            favoriteIds = ids.orEmpty()
            updateFavoriteButton()
        }
        libraryViewModel.message.observe(viewLifecycleOwner) { message ->
            if (!message.isNullOrBlank() && isAdded) {
                Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
                libraryViewModel.consumeMessage()
            }
        }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            updateAudioQualityButton()
            updateFavoriteButton()
            if (song == null) {
                lyricParseJob?.cancel()
                lyricLines = emptyList()
                lyricsAdapter.submitLyrics(emptyList())
                currentActiveIndex = -1
                applySongToViews(null)
                return@observe
            }
            // Cover is in local metadata; lyrics need a network (or memory) fetch — kick it off
            // as soon as the full player opens, without waiting for stream prepare / play.
            if (song.lyric.isNullOrBlank()) {
                PlaybackCoordinator.ensureLyricsForCurrentSong()
            }
            applySongToViews(song)
        }

        // Apply current song immediately if available
        musicViewModel.currentSong.value?.let { song ->
            if (song.lyric.isNullOrBlank()) {
                PlaybackCoordinator.ensureLyricsForCurrentSong()
            }
            applySongToViews(song)
        }
    }

    private fun installHandleDragToDismiss() {
        val threshold = HANDLE_DISMISS_DISTANCE_DP * resources.displayMetrics.density
        binding.btnClose.installDownwardDragToDismiss(
            dismissDistancePx = threshold,
            dragSlopPx = 12f * resources.displayMetrics.density
        ) {
            (activity as? MainActivity)?.animatePlayerBackground(expanded = false)
            dismiss()
        }
    }

    private fun showAudioQualityDialog() {
        val sheet = AudioQualityBottomSheet()
        sheet.onQualitySelected = { selectedLevel ->
            updateAudioQualityButton()
            if (musicViewModel.currentSong.value != null) {
                musicViewModel.reloadCurrentSongForAudioQualityChange()
            }
            Toast.makeText(
                requireContext(),
                getString(R.string.audio_quality_switched, selectedLevel.displayName),
                Toast.LENGTH_SHORT
            ).show()
        }
        sheet.show(parentFragmentManager, "audio_quality")
    }

    private fun updateAudioQualityButton() {
        if (_binding == null) return
        binding.btnAudioQuality.text = AudioQualityPreferences.getPreferredLevel(requireContext()).displayName
        updatePlaybackMeta()
    }

    private fun toggleFavoriteForCurrentSong() {
        val song = musicViewModel.currentSong.value ?: return
        val willFavorite = !favoriteIds.contains(song.id)
        libraryViewModel.setFavorite(song, willFavorite)
    }

    private fun showAddToPlaylistDialog(song: com.music.player.data.model.Song) {
        val playlists = libraryViewModel.playlists.value.orEmpty()
        if (playlists.isEmpty()) {
            MaterialAlertDialogBuilder(requireContext())
                .setTitle(R.string.user_playlist_pick_title)
                .setMessage(R.string.user_playlist_create_first)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.user_playlist_create_title) { _, _ ->
                    CreatePlaylistBottomSheet().apply {
                        onConfirm = { name, desc -> libraryViewModel.createPlaylist(name, desc) }
                    }.show(parentFragmentManager, "create_playlist")
                }
                .show()
            libraryViewModel.refreshPlaylists(silent = true, forceRefresh = false)
            return
        }

        val names = playlists.map { playlist ->
            val count = resources.getQuantityString(
                R.plurals.user_playlist_track_count,
                playlist.trackCount,
                playlist.trackCount
            )
            "${playlist.name} · $count"
        }.toTypedArray()
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.user_playlist_pick_title)
            .setItems(names) { _, which ->
                libraryViewModel.addSongToPlaylist(playlists[which].id, song)
            }
            .setNeutralButton(R.string.user_playlist_create_title) { _, _ ->
                CreatePlaylistBottomSheet().apply {
                    onConfirm = { name, desc -> libraryViewModel.createPlaylist(name, desc) }
                }.show(parentFragmentManager, "create_playlist")
            }
            .show()
    }

    private fun updateFavoriteButton() {
        if (_binding == null) return
        val song = musicViewModel.currentSong.value
        val isFavorite = song != null && favoriteIds.contains(song.id)
        // Top-right overflow is always-enabled chrome.
        binding.btnOverflow.isEnabled = true
        binding.btnOverflow.alpha = 1f
        binding.btnOverflow.imageTintList = ColorStateList.valueOf(Color.WHITE)
        binding.btnOverflow.contentDescription = getString(R.string.content_desc_more)
        // Heart uses brand red when liked; otherwise soft white on dark chrome.
        val likedRed = androidx.core.content.ContextCompat.getColor(requireContext(), R.color.favorite_red)
        val unliked = ColorUtils.setAlphaComponent(Color.WHITE, 0xB3)
        binding.btnFavorite.imageTintList = ColorStateList.valueOf(
            if (isFavorite) likedRed else unliked
        )
        binding.btnFavorite.alpha = if (song == null) 0.38f else 1f
        binding.btnFavorite.isEnabled = song != null
        binding.btnFavorite.contentDescription = getString(
            if (isFavorite) R.string.action_unfavorite else R.string.action_favorite
        )
        binding.menuFavoriteSong.text = getString(
            if (isFavorite) R.string.action_unfavorite else R.string.action_favorite
        )
    }

    private fun shareCurrentSong(song: com.music.player.data.model.Song) {
        val artist = song.artists.joinToString(", ") { it.name }.trim()
        val album = song.album.name.trim()
        val text = listOfNotNull(
            listOf(song.name.trim(), artist).filter { it.isNotBlank() }.joinToString(" - "),
            album.takeIf { it.isNotBlank() }
        ).joinToString("\n")
        runCatching {
            startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }, getString(R.string.player_share_song)))
        }.onFailure {
            Toast.makeText(requireContext(), R.string.player_share_unavailable, Toast.LENGTH_SHORT).show()
        }
    }

    private fun openCurrentAlbum(song: com.music.player.data.model.Song) {
        val albumId = song.album.id.trim()
        if (albumId.isBlank()) {
            Toast.makeText(requireContext(), R.string.player_album_unavailable, Toast.LENGTH_SHORT).show()
            return
        }
        val main = activity as? MainActivity
        if (main == null) {
            Toast.makeText(requireContext(), R.string.player_album_unavailable, Toast.LENGTH_SHORT).show()
            return
        }
        main.pushDetail(
            AlbumSongsFragment.newInstance(
                albumId = albumId,
                albumName = song.album.name,
                artistNames = song.artists.joinToString(", ") { it.name },
                coverUrl = song.album.picUrl
            )
        )
    }

    private fun syncSkipButtons() {
        val prevEnabled = musicViewModel.canSkipPrevious.value == true
        val nextEnabled = musicViewModel.queue.value.orEmpty().isNotEmpty()
        setControlEnabled(binding.btnPrev, prevEnabled)
        setControlEnabled(binding.btnNext, nextEnabled)
    }

    private fun setControlEnabled(button: android.widget.ImageButton, enabled: Boolean) {
        button.isEnabled = enabled
        button.alpha = 1f
        (button.parent as? View)?.alpha = if (enabled) 1f else 0.4f
    }

    private fun applySongToViews(song: com.music.player.data.model.Song?) {
        if (song == null) {
            binding.tvSheetTitle.text = getString(R.string.current_playing_empty)
            binding.tvSheetSubtitle.text = getString(R.string.current_playing_hint)
            binding.tvSheetSubtitle.isVisible = true
            binding.tvControlSongTitle.text = getString(R.string.current_playing_empty)
            binding.tvControlSongArtist.text = getString(R.string.current_playing_hint)
            binding.tvControlSongArtist.isVisible = true
            binding.tvSheetMetaDetail.text = getString(R.string.now_playing_meta_no_song)
            immersiveBackground?.setImageUrl(null)
            lyricsAdapter.submitLyrics(emptyList())
            tvLyricsPlain?.visibility = View.VISIBLE
            rvLyrics?.visibility = View.GONE
            tvLyricsPlain?.text = getString(R.string.lyrics_placeholder)
            ivCoverBig?.setImageResource(R.drawable.ic_music_note_24)
            ivCoverBig?.imageTintList = ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
            showCoverStage(immediate = true)
            return
        }

        val artistText = song.artists.joinToString(", ") { it.name }
        binding.tvSheetTitle.text = song.name
        binding.tvSheetSubtitle.text = artistText
        binding.tvSheetSubtitle.isVisible = artistText.isNotBlank()
        binding.tvControlSongTitle.text = song.name
        binding.tvControlSongArtist.text = artistText
        binding.tvControlSongArtist.isVisible = artistText.isNotBlank()
        updatePlaybackMeta()

        // Clear the previous song immediately, then parse the new LRC off the main thread.
        lyricParseJob?.cancel()
        val renderToken = ++lyricRenderToken
        lyricLines = emptyList()
        currentActiveIndex = -1
        lyricsAdapter.submitLyrics(emptyList())
        tvLyricsPlain?.visibility = View.VISIBLE
        rvLyrics?.visibility = View.GONE
        tvLyricsPlain?.text = if (song.lyric.isNullOrBlank()) {
            getString(R.string.lyrics_loading)
        } else {
            getString(R.string.lyrics_placeholder)
        }
        lyricParseJob = viewLifecycleOwner.lifecycleScope.launch {
            val parsed = withContext(Dispatchers.Default) {
                LyricsParser.parse(song.lyric)
            }
            if (renderToken != lyricRenderToken || musicViewModel.currentSong.value?.id != song.id) {
                return@launch
            }
            lyricLines = parsed
            if (parsed.isNotEmpty()) {
                tvLyricsPlain?.visibility = View.GONE
                rvLyrics?.visibility = View.VISIBLE
                lyricsAdapter.submitLyrics(parsed) {
                    if (_binding != null && renderToken == lyricRenderToken) {
                        syncActiveLyric(scroll = showingLyrics)
                    }
                }
            } else {
                tvLyricsPlain?.text = song.lyric?.takeIf { it.isNotBlank() }
                    ?: getString(R.string.lyrics_not_available)
            }
        }

        // Load cover image with crossfade on track change
        val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
        immersiveBackground?.setImageUrl(coverUrl)
        if (coverUrl == null) {
            ivCoverBig?.setImageResource(R.drawable.ic_music_note_24)
            ivCoverBig?.imageTintList = ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
        } else {
            ivCoverBig?.imageTintList = null
            ivCoverBig?.let { iv ->
                Glide.with(this)
                    .load(coverUrl)
                    .placeholder(R.drawable.ic_music_note_24)
                    .centerCrop()
                    .transition(DrawableTransitionOptions.withCrossFade(COVER_CROSSFADE_MS))
                    .into(iv)
            }
        }

        // Start lyric sync and rotation
        startLyricUpdates()
        syncCoverRotation()
    }

    private fun showCoverStage(immediate: Boolean = false) {
        if (!immediate && !showingLyrics) {
            syncCoverRotation()
            return
        }
        showingLyrics = false
        // Keep transport bar visible on both cover and lyrics (NetEase).
        binding.controlsBar.visibility = View.VISIBLE
        if (immediate) {
            coverStage?.animate()?.cancel()
            lyricsStage?.animate()?.cancel()
            coverStage?.visibility = View.VISIBLE
            coverStage?.alpha = 1f
            coverStage?.scaleX = 1f
            coverStage?.scaleY = 1f
            lyricsStage?.visibility = View.GONE
        } else {
            coverStage?.animate()?.cancel()
            lyricsStage?.animate()?.cancel()
            coverStage?.visibility = View.VISIBLE
            coverStage?.alpha = 0f
            coverStage?.scaleX = 0.985f
            coverStage?.scaleY = 0.985f
            lyricsStage?.animate()
                ?.alpha(0f)
                ?.scaleX(0.985f)
                ?.scaleY(0.985f)
                ?.setDuration(STAGE_ANIMATION_MS)
                ?.setInterpolator(AccelerateDecelerateInterpolator())
                ?.withEndAction { lyricsStage?.visibility = View.GONE }
                ?.start()
            coverStage?.animate()
                ?.alpha(1f)
                ?.scaleX(1f)
                ?.scaleY(1f)
                ?.setDuration(STAGE_ANIMATION_MS)
                ?.setInterpolator(AccelerateDecelerateInterpolator())
                ?.start()
        }
        syncCoverRotation()
        val player = (activity as? MainActivity)?.player
        syncGlowWithPlayback(player?.isPlaying == true, true)
    }

    private fun showLyricsStage() {
        if (showingLyrics) {
            syncActiveLyric(scroll = true)
            return
        }
        showingLyrics = true
        binding.controlsBar.visibility = View.VISIBLE
        lyricsStage?.visibility = View.VISIBLE
        coverStage?.animate()?.cancel()
        lyricsStage?.animate()?.cancel()
        lyricsStage?.alpha = 0f
        lyricsStage?.scaleX = 0.985f
        lyricsStage?.scaleY = 0.985f
        coverStage?.animate()
            ?.alpha(0f)
            ?.scaleX(0.985f)
            ?.scaleY(0.985f)
            ?.setDuration(STAGE_ANIMATION_MS)
            ?.setInterpolator(AccelerateDecelerateInterpolator())
            ?.withEndAction { coverStage?.visibility = View.GONE }
            ?.start()
        lyricsStage?.animate()
            ?.alpha(1f)
            ?.scaleX(1f)
            ?.scaleY(1f)
            ?.setDuration(STAGE_ANIMATION_MS)
            ?.setInterpolator(AccelerateDecelerateInterpolator())
            ?.start()
        pauseCoverRotation()
        syncGlowWithPlayback(false, false)
        syncActiveLyric(scroll = true)
    }

    private fun syncPlayPauseIcon(isPlaying: Boolean) {
        val icon = if (isPlaying) R.drawable.ic_pause_24 else R.drawable.ic_play_24
        val contentDesc = if (isPlaying) R.string.content_desc_pause else R.string.content_desc_play
        binding.btnPlayPause.setImageResource(icon)
        binding.btnPlayPause.contentDescription = getString(contentDesc)
        syncCoverRotation()
        syncGlowWithPlayback(isPlaying, !showingLyrics)
    }

    private fun updatePlaybackMeta() {
        if (_binding == null) return
        val quality = AudioQualityPreferences.getPreferredLevel(requireContext()).displayName
        val currentSong = musicViewModel.currentSong.value
        val nextSongTitle = musicViewModel.queue.value.orEmpty()
            .firstOrNull()
            ?.name
            ?.trim()
            .orEmpty()
        binding.tvSheetMetaDetail.text = when {
            currentSong == null -> getString(R.string.now_playing_meta_no_song)
            nextSongTitle.isNotBlank() -> getString(R.string.now_playing_meta_with_next, quality, nextSongTitle)
            !currentSong.lyric.isNullOrBlank() -> getString(R.string.now_playing_meta_with_lyrics, quality)
            else -> getString(R.string.now_playing_meta_without_queue, quality)
        }
    }

    private fun updateFullscreenContentPadding() {
        if (_binding == null) return
        binding.playerContent.root.updatePadding(
            left = contentPaddingStart,
            top = contentPaddingTop,
            right = contentPaddingEnd,
            bottom = contentPaddingBottom
        )
    }

    // ── Cover Rotation (disc style) ──────────────────────────────

    private fun syncCoverRotation() {
        val player = (activity as? MainActivity)?.player
        if (!showingLyrics && player?.isPlaying == true) {
            startCoverRotation()
        } else {
            stopCoverRotation()
        }
    }

    private fun startCoverRotation() {
        val target = discContainer ?: return
        if (coverRotateAnimator?.isRunning == true) return
        coverRotateAnimator = ObjectAnimator.ofPropertyValuesHolder(
            target,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, 1.018f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, 1.018f)
        ).apply {
            duration = COVER_PULSE_DURATION_MS
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            interpolator = AccelerateDecelerateInterpolator()
        }.also { it.start() }
    }

    private fun pauseCoverRotation() {
        stopCoverRotation()
    }

    private fun stopCoverRotation() {
        coverRotateAnimator?.cancel()
        coverRotateAnimator = null
        if (_binding != null) {
            discContainer?.rotation = 0f
            ivCoverBig?.rotation = 0f
            discContainer?.scaleX = 1f
            discContainer?.scaleY = 1f
        }
    }

    // ── Glow Animation ─────────────────────────────────────────────

    private fun startGlowAnimation() {
        val halo = viewGlowHalo ?: return
        glowAnimator?.cancel()
        glowAnimator = ObjectAnimator.ofFloat(halo, "alpha", 0.3f, 0.9f, 0.3f).apply {
            duration = 2000L
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
        }.also { glowAnimator = it }
        halo.visibility = View.VISIBLE
        glowAnimator?.start()
    }

    private fun stopGlowAnimation() {
        glowAnimator?.cancel()
        glowAnimator = null
        viewGlowHalo?.visibility = View.INVISIBLE
    }

    @Suppress("UNUSED_PARAMETER")
    private fun syncGlowWithPlayback(isPlaying: Boolean, showingCover: Boolean) {
        stopGlowAnimation()
    }

    // ── Play mode ─────────────────────────────────────────────────

    private fun syncPlayModeIcon() {
        val player = (activity as? MainActivity)?.player ?: return
        val (icon, desc) = when (PlaybackModeController.resolve(player)) {
            PlaybackMode.SHUFFLE -> R.drawable.ic_shuffle_24 to R.string.content_desc_shuffle
            PlaybackMode.REPEAT_ALL -> R.drawable.ic_repeat_24 to R.string.content_desc_repeat
            PlaybackMode.REPEAT_ONE -> R.drawable.ic_repeat_one_24 to R.string.content_desc_repeat
        }
        binding.btnPlayMode.setImageResource(icon)
        binding.btnPlayMode.contentDescription = getString(desc)
        // Soft white on immersive chrome (not brand primary).
        binding.btnPlayMode.imageTintList =
            ColorStateList.valueOf(ColorUtils.setAlphaComponent(Color.WHITE, 0xB3))
    }

    // ── Lyrics sync ───────────────────────────────────────────────

    private fun startLyricUpdates() {
        lyricJob?.cancel()
        lyricJob = viewLifecycleOwner.lifecycleScope.launch {
            while (isActive) {
                val player = (activity as? MainActivity)?.player
                if (player != null && showingLyrics && rvLyrics?.visibility == View.VISIBLE && lyricLines.isNotEmpty()) {
                    syncActiveLyric()
                }
                delay(250)
            }
        }
    }

    private fun syncActiveLyric(scroll: Boolean = false) {
        val player = (activity as? MainActivity)?.player ?: return
        if (lyricLines.isEmpty()) return
        val index = LyricsParser.findActiveIndex(lyricLines, player.currentPosition)
        val activeLineChanged = index != currentActiveIndex
        if (activeLineChanged) {
            currentActiveIndex = index
            lyricsAdapter.setActiveIndex(index)
        }
        if (index >= 0 && !isUserScrollingLyrics && (activeLineChanged || scroll)) {
            if (scroll) {
                rvLyrics?.post { centerLyricAt(index) }
            } else {
                centerLyricAt(index)
            }
        }
    }

    private fun centerLyricAt(position: Int) {
        val layoutManager = rvLyrics?.layoutManager as? LinearLayoutManager ?: return
        val recyclerView = rvLyrics ?: return
        layoutManager.scrollToPosition(position)
        recyclerView.post {
            if (!showingLyrics || isUserScrollingLyrics) return@post
            val line = layoutManager.findViewByPosition(position) ?: return@post
            val lineCenter = line.top + line.height / 2
            val viewportCenter = recyclerView.height / 2
            recyclerView.scrollBy(0, lineCenter - viewportCenter)
        }
    }

    // ── Progress updates ──────────────────────────────────────────

    private fun startProgressUpdates() {
        progressJob?.cancel()
        progressJob = viewLifecycleOwner.lifecycleScope.launch {
            while (isActive) {
                val durationMs = PlaybackCoordinator.displayDurationMs()
                val positionMs = PlaybackCoordinator.displayPositionMs()
                val hasDuration = durationMs > 0L
                val safeDuration = if (hasDuration) durationMs else 1L

                binding.sliderProgress.valueTo = safeDuration.toFloat()
                binding.sliderProgress.isEnabled = hasDuration

                binding.tvTotalTime.text = if (hasDuration) {
                    "-${formatTime((durationMs - positionMs).coerceAtLeast(0L))}"
                } else {
                    "-00:00"
                }
                if (!isUserSeeking) {
                    binding.sliderProgress.value = positionMs.coerceAtMost(safeDuration).toFloat()
                    binding.tvCurrentTime.text = formatTime(positionMs)
                }

                delay(250)
            }
        }
    }

    // ── Utilities ─────────────────────────────────────────────────

    private fun themeColor(attrResId: Int): Int {
        val typedValue = TypedValue()
        requireContext().theme.resolveAttribute(attrResId, typedValue, true)
        return typedValue.data
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun formatTime(ms: Long): String {
        val totalSeconds = (ms / 1000L).coerceAtLeast(0L)
        val seconds = (totalSeconds % 60).toInt()
        val minutes = ((totalSeconds / 60) % 60).toInt()
        val hours = (totalSeconds / 3600).toInt()
        return if (hours > 0) {
            String.format(Locale.getDefault(), "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.getDefault(), "%02d:%02d", minutes, seconds)
        }
    }

    private fun View.applyStatusBarInsetPadding() {
        applySystemBarInsetPadding(applyTop = true)
    }

    private fun View.applyNavigationBarInsetPadding() {
        applySystemBarInsetPadding(applyBottom = true)
    }

    private fun View.applySystemBarInsetPadding(
        applyLeft: Boolean = false,
        applyTop: Boolean = false,
        applyRight: Boolean = false,
        applyBottom: Boolean = false
    ) {
        val initialLeft = paddingLeft
        val initialTop = paddingTop
        val initialRight = paddingRight
        val initialBottom = paddingBottom

        ViewCompat.setOnApplyWindowInsetsListener(this) { view, insets ->
            val bars = insets.getInsetsIgnoringVisibility(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            view.updatePadding(
                left = initialLeft + if (applyLeft) bars.left else 0,
                top = initialTop + if (applyTop) bars.top else 0,
                right = initialRight + if (applyRight) bars.right else 0,
                bottom = initialBottom + if (applyBottom) bars.bottom else 0
            )
            insets
        }

        if (isAttachedToWindow) {
            requestApplyInsets()
        } else {
            addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) {
                    v.removeOnAttachStateChangeListener(this)
                    v.requestApplyInsets()
                }

                override fun onViewDetachedFromWindow(v: View) = Unit
            })
        }
    }

    override fun onDestroyView() {
        (activity as? MainActivity)?.player?.removeListener(playerListener)
        lyricJob?.cancel()
        lyricJob = null
        lyricParseJob?.cancel()
        lyricParseJob = null
        progressJob?.cancel()
        progressJob = null
        stopCoverRotation()
        stopGlowAnimation()
        immersiveBackground?.clear()
        immersiveBackground = null
        _binding = null
        super.onDestroyView()
    }
}
