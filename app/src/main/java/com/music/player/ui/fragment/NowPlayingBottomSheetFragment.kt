package com.music.player.ui.fragment

import android.content.res.ColorStateList
import android.os.Bundle
import android.os.Build
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.util.TypedValue
import android.view.GestureDetector
import android.view.WindowManager
import android.view.MotionEvent
import android.view.animation.LinearInterpolator
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
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.data.model.LyricLine
import com.music.player.databinding.BottomSheetNowPlayingBinding
import com.music.player.ui.adapter.LyricsAdapter
import com.music.player.ui.lyrics.LyricsParser
import com.music.player.ui.util.PlayerUiStyler
import com.music.player.ui.viewmodel.MusicViewModel
import androidx.media3.common.Player
import androidx.media3.common.C
import com.google.android.material.slider.Slider
import com.music.player.data.settings.AudioQualityPreferences
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.music.player.ui.viewmodel.LibraryViewModel

class NowPlayingBottomSheetFragment : DialogFragment() {

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
    private var progressJob: Job? = null
    private var currentActiveIndex: Int = -1
    private var isUserSeeking: Boolean = false
    private var coverRotateAnimator: ObjectAnimator? = null
    private var favoriteIds: Set<String> = emptySet()
    private var showingLyrics: Boolean = false

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

    override fun onStart() {
        super.onStart()

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
            val isNightMode =
                (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                    android.content.res.Configuration.UI_MODE_NIGHT_YES
            controller.isAppearanceLightStatusBars = !isNightMode
            controller.isAppearanceLightNavigationBars = !isNightMode
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        }

        startLyricUpdates()
        startProgressUpdates()
    }

    override fun onStop() {
        lyricJob?.cancel()
        lyricJob = null
        progressJob?.cancel()
        progressJob = null
        stopCoverRotation()
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

        coverStage?.setOnClickListener { showLyricsStage() }
        lyricsStage?.setOnClickListener { showCoverStage() }
        showCoverStage(immediate = true)

        // Setup lyrics RecyclerView
        rvLyrics?.layoutManager = LinearLayoutManager(requireContext())
        rvLyrics?.adapter = lyricsAdapter
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

        binding.btnClose.setOnClickListener { dismiss() }
        binding.btnAudioQuality.setOnClickListener { showAudioQualityDialog() }
        binding.btnFavorite.setOnClickListener { toggleFavoriteForCurrentSong() }
        binding.btnQueue.setOnClickListener {
            QueueBottomSheetFragment().show(parentFragmentManager, "queue")
        }
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

        binding.btnPrev.setOnClickListener { musicViewModel.skipPrevious() }
        binding.btnNext.setOnClickListener { musicViewModel.skipNext() }
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
            val mode = currentPlayMode(p)
            val next = when (mode) {
                PlayMode.SHUFFLE -> PlayMode.REPEAT_ALL
                PlayMode.REPEAT_ALL -> PlayMode.REPEAT_ONE
                PlayMode.REPEAT_ONE -> PlayMode.SHUFFLE
            }
            applyPlayMode(p, next)
            syncPlayModeIcon()
        }

        musicViewModel.queue.observe(viewLifecycleOwner) {
            syncSkipButtons()
        }
        musicViewModel.canSkipPrevious.observe(viewLifecycleOwner) {
            syncSkipButtons()
        }
        libraryViewModel.favoriteIds.observe(viewLifecycleOwner) { ids ->
            favoriteIds = ids.orEmpty()
            updateFavoriteButton()
        }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            updateAudioQualityButton()
            updateFavoriteButton()
            if (song == null) {
                lyricLines = emptyList()
                lyricsAdapter.submitList(emptyList())
                currentActiveIndex = -1
                applySongToViews(null)
                return@observe
            }
            applySongToViews(song)
        }

        // Apply current song immediately if available
        musicViewModel.currentSong.value?.let { applySongToViews(it) }
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
                "已切换音质：${selectedLevel.displayName}",
                Toast.LENGTH_SHORT
            ).show()
        }
        sheet.show(parentFragmentManager, "audio_quality")
    }

    private fun updateAudioQualityButton() {
        if (_binding == null) return
        binding.btnAudioQuality.text = AudioQualityPreferences.getPreferredLevel(requireContext()).displayName
    }

    private fun toggleFavoriteForCurrentSong() {
        val song = musicViewModel.currentSong.value ?: return
        val willFavorite = !favoriteIds.contains(song.id)
        libraryViewModel.setFavorite(song, willFavorite)
    }

    private fun updateFavoriteButton() {
        if (_binding == null) return
        val song = musicViewModel.currentSong.value
        val isFavorite = song != null && favoriteIds.contains(song.id)
        binding.btnFavorite.isEnabled = song != null
        binding.btnFavorite.alpha = if (song == null) 0.38f else 1f
        binding.btnFavorite.imageTintList = ColorStateList.valueOf(
            themeColor(if (isFavorite) R.attr.brandPrimary else R.attr.textSecondary)
        )
        binding.btnFavorite.contentDescription = getString(
            if (isFavorite) R.string.action_unfavorite else R.string.action_favorite
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
            lyricsAdapter.submitList(emptyList())
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

        // Parse and display lyrics
        val parsed = LyricsParser.parse(song.lyric)
        lyricLines = parsed
        currentActiveIndex = -1
        if (parsed.isNotEmpty()) {
            lyricsAdapter.submitList(parsed)
            tvLyricsPlain?.visibility = View.GONE
            rvLyrics?.visibility = View.VISIBLE
            rvLyrics?.scrollToPosition(0)
        } else {
            lyricsAdapter.submitList(emptyList())
            tvLyricsPlain?.visibility = View.VISIBLE
            rvLyrics?.visibility = View.GONE
            tvLyricsPlain?.text = song.lyric?.takeIf { it.isNotBlank() }
                ?: getString(R.string.lyrics_placeholder)
        }

        // Load cover image
        val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
        if (coverUrl == null) {
            ivCoverBig?.setImageResource(R.drawable.ic_music_note_24)
            ivCoverBig?.imageTintList = ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
        } else {
            ivCoverBig?.imageTintList = null
            ivCoverBig?.let { iv ->
                Glide.with(this)
                    .load(coverUrl)
                    .placeholder(R.drawable.ic_music_note_24)
                    .circleCrop()
                    .into(iv)
            }
        }

        // Start lyric sync and rotation
        startLyricUpdates()
        syncCoverRotation()
    }

    private fun showCoverStage(immediate: Boolean = false) {
        showingLyrics = false
        coverStage?.visibility = View.VISIBLE
        lyricsStage?.visibility = View.GONE
        if (!immediate) {
            coverStage?.alpha = 1f
            lyricsStage?.alpha = 1f
        }
        syncCoverRotation()
    }

    private fun showLyricsStage() {
        showingLyrics = true
        lyricsStage?.visibility = View.VISIBLE
        coverStage?.visibility = View.GONE
        lyricsStage?.alpha = 1f
        coverStage?.alpha = 1f
        pauseCoverRotation()
    }

    private fun syncPlayPauseIcon(isPlaying: Boolean) {
        val icon = if (isPlaying) R.drawable.ic_pause_24 else R.drawable.ic_play_24
        val contentDesc = if (isPlaying) R.string.content_desc_pause else R.string.content_desc_play
        binding.btnPlayPause.setImageResource(icon)
        binding.btnPlayPause.contentDescription = getString(contentDesc)
        syncCoverRotation()
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
        if (_binding == null) return
        val player = (activity as? MainActivity)?.player ?: return
        if (!player.isPlaying) {
            pauseCoverRotation()
            return
        }
        startCoverRotation()
    }

    private fun startCoverRotation() {
        val target = discContainer ?: ivCoverBig ?: return

        val animator = coverRotateAnimator
        if (animator != null && animator.target !== target) {
            animator.cancel()
            coverRotateAnimator = null
        }

        val newAnimator = coverRotateAnimator ?: ObjectAnimator.ofFloat(target, View.ROTATION, 0f, 360f).apply {
            duration = 12000L
            interpolator = LinearInterpolator()
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
        }.also { coverRotateAnimator = it }

        if (!newAnimator.isStarted) {
            target.rotation = 0f
            newAnimator.start()
        } else {
            newAnimator.resume()
        }
    }

    private fun pauseCoverRotation() {
        coverRotateAnimator?.let { animator ->
            if (animator.isStarted) animator.pause()
        }
    }

    private fun stopCoverRotation() {
        coverRotateAnimator?.cancel()
        coverRotateAnimator = null
        if (_binding != null) {
            discContainer?.rotation = 0f
            ivCoverBig?.rotation = 0f
        }
    }

    // ── Play mode ─────────────────────────────────────────────────

    private enum class PlayMode {
        SHUFFLE,
        REPEAT_ALL,
        REPEAT_ONE
    }

    private fun currentPlayMode(player: Player): PlayMode {
        return when {
            player.shuffleModeEnabled -> PlayMode.SHUFFLE
            player.repeatMode == Player.REPEAT_MODE_ONE -> PlayMode.REPEAT_ONE
            else -> PlayMode.REPEAT_ALL
        }
    }

    private fun applyPlayMode(player: Player, mode: PlayMode) {
        when (mode) {
            PlayMode.SHUFFLE -> {
                player.shuffleModeEnabled = true
                player.repeatMode = Player.REPEAT_MODE_OFF
            }
            PlayMode.REPEAT_ALL -> {
                player.shuffleModeEnabled = false
                player.repeatMode = Player.REPEAT_MODE_ALL
            }
            PlayMode.REPEAT_ONE -> {
                player.shuffleModeEnabled = false
                player.repeatMode = Player.REPEAT_MODE_ONE
            }
        }
    }

    private fun syncPlayModeIcon() {
        val player = (activity as? MainActivity)?.player ?: return
        val (icon, desc) = when (currentPlayMode(player)) {
            PlayMode.SHUFFLE -> R.drawable.ic_shuffle_24 to R.string.content_desc_shuffle
            PlayMode.REPEAT_ALL -> R.drawable.ic_repeat_24 to R.string.content_desc_repeat
            PlayMode.REPEAT_ONE -> R.drawable.ic_repeat_one_24 to R.string.content_desc_repeat
        }
        binding.btnPlayMode.setImageResource(icon)
        binding.btnPlayMode.contentDescription = getString(desc)
        binding.btnPlayMode.imageTintList =
            ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
    }

    // ── Lyrics sync ───────────────────────────────────────────────

    private fun startLyricUpdates() {
        val player = (activity as? MainActivity)?.player ?: return
        lyricJob?.cancel()
        lyricJob = viewLifecycleOwner.lifecycleScope.launch {
            while (isActive) {
                if (rvLyrics?.visibility == View.VISIBLE && lyricLines.isNotEmpty()) {
                    val index = LyricsParser.findActiveIndex(lyricLines, player.currentPosition)
                    if (index != currentActiveIndex) {
                        currentActiveIndex = index
                        lyricsAdapter.setActiveIndex(index)
                        if (index >= 0) {
                            smoothScrollLyricToCenter(index.coerceAtLeast(0))
                        }
                    }
                }
                delay(250)
            }
        }
    }

    private fun smoothScrollLyricToCenter(position: Int) {
        val layoutManager = rvLyrics?.layoutManager as? LinearLayoutManager ?: return
        val scroller = object : LinearSmoothScroller(requireContext()) {
            override fun getVerticalSnapPreference(): Int = SNAP_TO_START

            override fun calculateDtToFit(
                viewStart: Int,
                viewEnd: Int,
                boxStart: Int,
                boxEnd: Int,
                snapPreference: Int
            ): Int {
                val viewCenter = viewStart + (viewEnd - viewStart) / 2
                val boxCenter = boxStart + (boxEnd - boxStart) / 2
                return boxCenter - viewCenter
            }
        }
        scroller.targetPosition = position
        layoutManager.startSmoothScroll(scroller)
    }

    // ── Progress updates ──────────────────────────────────────────

    private fun startProgressUpdates() {
        val player = (activity as? MainActivity)?.player ?: return
        progressJob?.cancel()
        progressJob = viewLifecycleOwner.lifecycleScope.launch {
            while (isActive) {
                val durationMs = player.duration
                val hasDuration = durationMs > 0L && durationMs != C.TIME_UNSET
                val safeDuration = if (hasDuration) durationMs else 1L

                binding.sliderProgress.valueTo = safeDuration.toFloat()
                binding.sliderProgress.isEnabled = hasDuration
                binding.tvTotalTime.text = formatTime(if (hasDuration) durationMs else 0L)

                val positionMs = player.currentPosition.coerceAtLeast(0L)
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
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
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
        progressJob?.cancel()
        progressJob = null
        stopCoverRotation()
        _binding = null
        super.onDestroyView()
    }
}
