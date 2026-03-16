package com.music.player.ui.fragment

import android.content.res.ColorStateList
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.drawable.ColorDrawable
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import androidx.core.view.doOnLayout
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import com.bumptech.glide.Glide
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.data.model.LyricLine
import com.music.player.databinding.BottomSheetNowPlayingBinding
import com.music.player.ui.adapter.LyricsAdapter
import com.music.player.ui.lyrics.LyricsParser
import com.music.player.ui.viewmodel.MusicViewModel
import androidx.media3.common.Player
import androidx.media3.common.C
import com.google.android.material.slider.Slider
import com.music.player.ui.util.StackBlur
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class NowPlayingBottomSheetFragment : BottomSheetDialogFragment() {

    private var _binding: BottomSheetNowPlayingBinding? = null
    private val binding: BottomSheetNowPlayingBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var lyricsAdapter: LyricsAdapter

    private var lyricLines: List<LyricLine> = emptyList()
    private var lyricJob: Job? = null
    private var progressJob: Job? = null
    private var backgroundJob: Job? = null
    private var blurredCoverBitmap: Bitmap? = null
    private var currentActiveIndex: Int = -1
    private var isUserSeeking: Boolean = false
    private var coverRotateAnimator: ObjectAnimator? = null

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

    override fun getTheme(): Int = R.style.ThemeOverlayMusicPlayerFullscreenBottomSheet

    override fun onStart() {
        super.onStart()

        (dialog as? BottomSheetDialog)?.let { bottomSheetDialog ->
            bottomSheetDialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            bottomSheetDialog.window?.setLayout(MATCH_PARENT, MATCH_PARENT)
            val bottomSheet =
                bottomSheetDialog.findViewById<FrameLayout>(com.google.android.material.R.id.design_bottom_sheet)
                    ?: return@let
            bottomSheet.background = ColorDrawable(Color.TRANSPARENT)
            bottomSheet.layoutParams = bottomSheet.layoutParams.apply { height = MATCH_PARENT }
            BottomSheetBehavior.from(bottomSheet).apply {
                state = BottomSheetBehavior.STATE_EXPANDED
                skipCollapsed = true
            }
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

        lyricsAdapter = LyricsAdapter()
        binding.rvLyrics.layoutManager = LinearLayoutManager(requireContext())
        binding.rvLyrics.adapter = lyricsAdapter
        binding.rvLyrics.doOnLayout {
            val minInset = dp(24)
            val inset = (it.height / 2 - minInset).coerceAtLeast(minInset)
            binding.rvLyrics.setPadding(
                binding.rvLyrics.paddingLeft,
                inset,
                binding.rvLyrics.paddingRight,
                inset
            )
        }

        binding.btnClose.setOnClickListener { dismiss() }
        binding.btnQueue.setOnClickListener {
            QueueBottomSheetFragment().show(parentFragmentManager, "queue")
        }

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
            if (p.isPlaying) {
                p.pause()
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

        binding.ivCoverBig.setOnClickListener { showLyrics() }
        binding.tvTitleSmall.setOnClickListener { showCover() }
        binding.tvArtistSmall.setOnClickListener { showCover() }

        musicViewModel.queue.observe(viewLifecycleOwner) {
            syncSkipButtons()
        }
        musicViewModel.canSkipPrevious.observe(viewLifecycleOwner) {
            syncSkipButtons()
        }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            if (song == null) {
                binding.tvTitleBig.text = getString(R.string.current_playing_empty)
                binding.tvArtistBig.text = getString(R.string.current_playing_hint)
                binding.tvTitleSmall.text = getString(R.string.current_playing_empty)
                binding.tvArtistSmall.text = getString(R.string.current_playing_hint)

                lyricLines = emptyList()
                lyricsAdapter.submitList(emptyList())
                binding.tvLyricsPlain.visibility = View.VISIBLE
                binding.rvLyrics.visibility = View.GONE
                binding.tvLyricsPlain.text = getString(R.string.lyrics_placeholder)
                currentActiveIndex = -1

                binding.ivCoverBig.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCoverBig.imageTintList = ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
                binding.ivCoverSmall.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCoverSmall.imageTintList =
                    ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))

                binding.ivBlurBackground.setImageDrawable(null)
                blurredCoverBitmap = null

                showCover()
                return@observe
            }

            binding.tvTitleBig.text = song.name
            binding.tvArtistBig.text = song.artists.joinToString(", ") { it.name }
            binding.tvTitleSmall.text = song.name
            binding.tvArtistSmall.text = song.artists.joinToString(", ") { it.name }

            val parsed = LyricsParser.parse(song.lyric)
            lyricLines = parsed
            currentActiveIndex = -1
            if (parsed.isNotEmpty()) {
                lyricsAdapter.submitList(parsed)
                binding.tvLyricsPlain.visibility = View.GONE
                binding.rvLyrics.visibility = View.VISIBLE
                binding.rvLyrics.scrollToPosition(0)
            } else {
                lyricsAdapter.submitList(emptyList())
                binding.tvLyricsPlain.visibility = View.VISIBLE
                binding.rvLyrics.visibility = View.GONE
                binding.tvLyricsPlain.text = song.lyric?.takeIf { it.isNotBlank() }
                    ?: getString(R.string.lyrics_placeholder)
            }

            val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
            if (coverUrl == null) {
                binding.ivCoverBig.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCoverBig.imageTintList = ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
                binding.ivCoverSmall.setImageResource(R.drawable.ic_music_note_24)
                binding.ivCoverSmall.imageTintList =
                    ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
                binding.ivBlurBackground.setImageDrawable(null)
                blurredCoverBitmap = null
            } else {
                binding.ivCoverBig.imageTintList = null
                binding.ivCoverSmall.imageTintList = null
                Glide.with(this)
                    .load(coverUrl)
                    .placeholder(R.drawable.ic_music_note_24)
                    .centerCrop()
                    .into(binding.ivCoverBig)

                loadBlurBackground(coverUrl)
            }

            if (binding.vfContent.displayedChild == 1) {
                startLyricUpdates()
                syncCoverRotation()
            }
        }
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
                StackBlur.blur(bitmap, radius = 18)
            }

            if (_binding != null) {
                blurredCoverBitmap = blurred
                binding.ivBlurBackground.setImageBitmap(blurred)
                binding.ivCoverSmall.imageTintList = null
                binding.ivCoverSmall.setImageBitmap(blurred)
            }
        }
    }

    private fun showCover() {
        binding.vfContent.displayedChild = 0
        lyricJob?.cancel()
        lyricJob = null
        startProgressUpdates()
        syncCoverRotation()
    }

    private fun showLyrics() {
        binding.vfContent.displayedChild = 1
        startLyricUpdates()
        startProgressUpdates()
        syncCoverRotation()
    }

    private fun syncPlayPauseIcon(isPlaying: Boolean) {
        val icon = if (isPlaying) R.drawable.ic_pause_24 else R.drawable.ic_play_24
        val contentDesc = if (isPlaying) R.string.content_desc_pause else R.string.content_desc_play
        binding.btnPlayPause.setImageResource(icon)
        binding.btnPlayPause.contentDescription = getString(contentDesc)
        syncCoverRotation()
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
        val target = if (binding.vfContent.displayedChild == 1) binding.ivCoverSmall else binding.ivCoverBig
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
            binding.ivCoverSmall.rotation = 0f
            binding.ivCoverBig.rotation = 0f
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
            ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
    }

    private fun startLyricUpdates() {
        val player = (activity as? MainActivity)?.player ?: return
        lyricJob?.cancel()
        lyricJob = viewLifecycleOwner.lifecycleScope.launch {
            while (isActive) {
                if (binding.rvLyrics.visibility == View.VISIBLE && lyricLines.isNotEmpty()) {
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
        val layoutManager = binding.rvLyrics.layoutManager as? LinearLayoutManager ?: return
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
}
