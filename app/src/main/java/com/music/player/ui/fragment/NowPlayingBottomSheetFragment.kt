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
import android.graphics.Bitmap
import android.graphics.drawable.ColorDrawable
import android.util.TypedValue
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.Toast
import androidx.core.view.WindowCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.doOnLayout
import androidx.core.view.updatePadding
import androidx.fragment.app.DialogFragment
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.viewpager2.widget.ViewPager2
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
import com.music.player.ui.util.StackBlur
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
    private lateinit var nowPlayingPagerAdapter: NowPlayingPagerAdapter

    // Page views - available after ViewPager2 creates them
    private var ivCoverBig: android.widget.ImageView? = null
    private var ivCoverSmall: android.widget.ImageView? = null
    private var tvTitleBig: android.widget.TextView? = null
    private var tvArtistBig: android.widget.TextView? = null
    private var tvTitleSmall: android.widget.TextView? = null
    private var tvArtistSmall: android.widget.TextView? = null
    private var rvLyrics: androidx.recyclerview.widget.RecyclerView? = null
    private var tvLyricsPlain: android.widget.TextView? = null

    private var lyricLines: List<LyricLine> = emptyList()
    private var lyricJob: Job? = null
    private var progressJob: Job? = null
    private var backgroundJob: Job? = null
    private var blurredCoverBitmap: Bitmap? = null
    private var currentActiveIndex: Int = -1
    private var isUserSeeking: Boolean = false
    private var coverRotateAnimator: ObjectAnimator? = null
    private var favoriteIds: Set<String> = emptySet()

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
            if (Build.VERSION.SDK_INT >= 31) {
                window.addFlags(WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
                window.setBackgroundBlurRadius(dp(56))
            }
            window.attributes = window.attributes.apply {
                width = MATCH_PARENT
                height = MATCH_PARENT
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                if (Build.VERSION.SDK_INT >= 31) {
                    blurBehindRadius = dp(24)
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
        backgroundJob?.cancel()
        backgroundJob = null
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

        // Setup ViewPager2 for cover/lyrics swipe
        nowPlayingPagerAdapter = NowPlayingPagerAdapter()
        binding.vpContent.adapter = nowPlayingPagerAdapter
        binding.vpContent.offscreenPageLimit = 1
        binding.vpContent.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                updatePageIndicator(position)
                if (position == 1) {
                    startLyricUpdates()
                } else {
                    lyricJob?.cancel()
                    lyricJob = null
                }
                startProgressUpdates()
                syncCoverRotation()
            }
        })

        // Wire up page views once ViewPager2 has inflated them
        binding.vpContent.post {
            val coverView = nowPlayingPagerAdapter.coverPage
            val lyricsView = nowPlayingPagerAdapter.lyricsPage
            if (coverView != null) {
                ivCoverBig = coverView.findViewById(R.id.ivCoverBig)
                tvTitleBig = coverView.findViewById(R.id.tvTitleBig)
                tvArtistBig = coverView.findViewById(R.id.tvArtistBig)
                ivCoverBig?.setOnClickListener { binding.vpContent.currentItem = 1 }
            }
            if (lyricsView != null) {
                ivCoverSmall = lyricsView.findViewById(R.id.ivCoverSmall)
                tvTitleSmall = lyricsView.findViewById(R.id.tvTitleSmall)
                tvArtistSmall = lyricsView.findViewById(R.id.tvArtistSmall)
                rvLyrics = lyricsView.findViewById(R.id.rvLyrics)
                tvLyricsPlain = lyricsView.findViewById(R.id.tvLyricsPlain)
                tvTitleSmall?.setOnClickListener { binding.vpContent.currentItem = 0 }
                tvArtistSmall?.setOnClickListener { binding.vpContent.currentItem = 0 }
                rvLyrics?.layoutManager = LinearLayoutManager(requireContext())
                rvLyrics?.adapter = lyricsAdapter
                rvLyrics?.doOnLayout {
                    val minInset = dp(24)
                    val inset = (it.height / 2 - minInset).coerceAtLeast(minInset)
                    (it as? androidx.recyclerview.widget.RecyclerView)?.setPadding(
                        it.paddingLeft, inset, it.paddingRight, inset
                    )
                }
            }
            // Apply any pending song data
            musicViewModel.currentSong.value?.let { applySongToPageViews(it) }
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

        ivCoverBig?.setOnClickListener { binding.vpContent.currentItem = 1 }
        tvTitleSmall?.setOnClickListener { binding.vpContent.currentItem = 0 }
        tvArtistSmall?.setOnClickListener { binding.vpContent.currentItem = 0 }

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
                binding.ivBlurBackground.setImageDrawable(null)
                blurredCoverBitmap = null
                applySongToPageViews(null)
                showCover()
                return@observe
            }
            applySongToPageViews(song)
        }
    }

    private fun showAudioQualityDialog() {
        val sheet = AudioQualityBottomSheet()
        sheet.onQualitySelected = { selectedLevel ->
            updateAudioQualityButton()
            if (musicViewModel.currentSong.value != null) {
                musicViewModel.reloadCurrentSongForAudioQualityChange()
            }
            android.widget.Toast.makeText(
                requireContext(),
                "已切换音质：${selectedLevel.displayName}",
                android.widget.Toast.LENGTH_SHORT
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
        button.alpha = if (enabled) 1f else 0.4f
    }

    private fun loadBlurBackground(url: String) {
        backgroundJob?.cancel()
        backgroundJob = viewLifecycleOwner.lifecycleScope.launch {
            val bitmap = runCatching {
                Glide.with(this@NowPlayingBottomSheetFragment)
                    .asBitmap()
                    .load(url)
                    .submit(360, 360)
                    .get()
            }.getOrNull() ?: return@launch

            val blurred = withContext(Dispatchers.Default) {
                StackBlur.blur(bitmap, radius = 24)
            }

            if (_binding != null) {
                blurredCoverBitmap = blurred
                binding.ivBlurBackground.setImageBitmap(blurred)
                ivCoverSmall?.imageTintList = null
                ivCoverSmall?.setImageBitmap(blurred)
            }
        }
    }

    private fun showCover() {
        binding.vpContent.currentItem = 0
        lyricJob?.cancel()
        lyricJob = null
        startProgressUpdates()
        syncCoverRotation()
    }

    private fun showLyrics() {
        binding.vpContent.currentItem = 1
        startLyricUpdates()
        startProgressUpdates()
        syncCoverRotation()
    }

    private fun updatePageIndicator(position: Int) {
        if (_binding == null) return
        val alpha = if (position == 0) 1f else 0.4f
        val alphaInv = if (position == 1) 1f else 0.4f
        binding.indicatorCover.alpha = alpha
        binding.indicatorLyrics.alpha = alphaInv
    }

    private fun applySongToPageViews(song: com.music.player.data.model.Song?) {
        if (song == null) {
            tvTitleBig?.text = getString(R.string.current_playing_empty)
            tvArtistBig?.text = getString(R.string.current_playing_hint)
            tvTitleSmall?.text = getString(R.string.current_playing_empty)
            tvArtistSmall?.text = getString(R.string.current_playing_hint)
            lyricsAdapter.submitList(emptyList())
            tvLyricsPlain?.visibility = View.VISIBLE
            rvLyrics?.visibility = View.GONE
            tvLyricsPlain?.text = getString(R.string.lyrics_placeholder)
            ivCoverBig?.setImageResource(R.drawable.ic_music_note_24)
            ivCoverBig?.imageTintList = ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
            ivCoverSmall?.setImageResource(R.drawable.ic_music_note_24)
            ivCoverSmall?.imageTintList = ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
            return
        }

        tvTitleBig?.text = song.name
        tvArtistBig?.text = song.artists.joinToString(", ") { it.name }
        tvTitleSmall?.text = song.name
        tvArtistSmall?.text = song.artists.joinToString(", ") { it.name }

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

        val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
        if (coverUrl == null) {
            ivCoverBig?.setImageResource(R.drawable.ic_music_note_24)
            ivCoverBig?.imageTintList = ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
            ivCoverSmall?.setImageResource(R.drawable.ic_music_note_24)
            ivCoverSmall?.imageTintList = ColorStateList.valueOf(themeColor(R.attr.brandPrimary))
            binding.ivBlurBackground.setImageDrawable(null)
            blurredCoverBitmap = null
        } else {
            ivCoverBig?.imageTintList = null
            ivCoverSmall?.imageTintList = null
            ivCoverBig?.let { iv ->
                Glide.with(this)
                    .load(coverUrl)
                    .placeholder(R.drawable.ic_music_note_24)
                    .circleCrop()
                    .into(iv)
            }
            loadBlurBackground(coverUrl)
        }

        if (binding.vpContent.currentItem == 1) {
            startLyricUpdates()
            syncCoverRotation()
        }
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
        val topInset = binding.topBar.bottom.coerceAtLeast(0)
        val bottomInset = (binding.root.height - binding.progressContainer.top).coerceAtLeast(0)
        binding.vpContent.updatePadding(
            top = topInset,
            bottom = bottomInset
        )
    }

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
        val target = if (binding.vpContent.currentItem == 1) ivCoverSmall else ivCoverBig
        if (target == null) return
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
            ivCoverSmall?.rotation = 0f
            ivCoverBig?.rotation = 0f
        }
    }

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

    private fun themeColor(attrResId: Int): Int {
        val typedValue = TypedValue()
        requireContext().theme.resolveAttribute(attrResId, typedValue, true)
        return typedValue.data
    }

    private fun startLyricUpdates() {
        val player = (activity as? MainActivity)?.player ?: return
        lyricJob?.cancel()
        lyricJob = viewLifecycleOwner.lifecycleScope.launch {
            while (isActive) {
                if (rvLyrics?.visibility == View.VISIBLE && lyricLines.isNotEmpty() && binding.vpContent.currentItem == 1) {
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

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

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
        backgroundJob?.cancel()
        backgroundJob = null
        stopCoverRotation()
        _binding = null
        super.onDestroyView()
    }

    inner class NowPlayingPagerAdapter : androidx.recyclerview.widget.RecyclerView.Adapter<NowPlayingPagerAdapter.PageVH>() {
        var coverPage: View? = null
            private set
        var lyricsPage: View? = null
            private set

        inner class PageVH(val view: View) : androidx.recyclerview.widget.RecyclerView.ViewHolder(view)

        override fun getItemCount() = 2

        override fun getItemViewType(position: Int) = position

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PageVH {
            val inflater = LayoutInflater.from(parent.context)
            val view = if (viewType == 0) {
                inflater.inflate(R.layout.page_now_playing_cover, parent, false).also { coverPage = it }
            } else {
                inflater.inflate(R.layout.page_now_playing_lyrics, parent, false).also { lyricsPage = it }
            }
            return PageVH(view)
        }

        override fun onBindViewHolder(holder: PageVH, position: Int) = Unit
    }
}
