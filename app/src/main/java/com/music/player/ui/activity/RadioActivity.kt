package com.music.player.ui.activity

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.Chip
import com.music.player.R
import com.music.player.data.model.Album
import com.music.player.data.model.Artist
import com.music.player.data.model.RadioStation
import com.music.player.data.radio.RadioApiClient
import com.music.player.data.radio.RadioRecentStore
import com.music.player.data.radio.RadioRegionHelper
import com.music.player.databinding.ActivityRadioBinding
import com.music.player.databinding.ItemRadioStationBinding
import com.music.player.playback.PlaybackCoordinator
import com.music.player.playback.PlaybackService
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyNavigationBarInsetPadding
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.resolveThemeColor
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Live radio directory — search, region chips, recent, pull-to-refresh, now-playing dock.
 */
@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
class RadioActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRadioBinding
    private lateinit var adapter: StationAdapter
    private lateinit var recentStore: RadioRecentStore

    private var allStations: List<RadioStation> = emptyList()
    private var recentStations: List<RadioStation> = emptyList()
    private var selectedChip: String = RadioRegionHelper.ALL
    private var loadJob: Job? = null
    private var playingId: String? = null
    private var isRadioPlaying: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityRadioBinding.inflate(layoutInflater)
        setContentView(binding.root)

        recentStore = RadioRecentStore(this)
        recentStations = recentStore.load()

        val lightBars = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) !=
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(rootView = binding.root, lightSystemBars = lightBars)
        binding.toolbar.applyStatusBarInsetPadding()
        binding.recyclerView.applyNavigationBarInsetPadding()
        binding.nowPlayingBar.applyNavigationBarInsetPadding()

        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.toolbar.inflateMenu(R.menu.menu_radio)
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_refresh -> {
                    loadStations(forceRefresh = true)
                    true
                }
                else -> false
            }
        }

        adapter = StationAdapter { station -> onStationClick(station) }
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.adapter = adapter
        binding.recyclerView.setHasFixedSize(true)
        binding.recyclerView.itemAnimator = null

        binding.swipeRefresh.setColorSchemeColors(resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener { loadStations(forceRefresh = true) }

        binding.btnRetry.setOnClickListener { loadStations(forceRefresh = true) }
        binding.btnRetry.bindPressFeedback(PressFeedback.Style.BUTTON)

        binding.etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                applyFilter()
            }
        })
        binding.etSearch.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                hideKeyboard()
                true
            } else false
        }

        binding.btnNowPlayPause.setOnClickListener {
            PlaybackCoordinator.togglePlayPause()
            refreshPlayingUiFromPlayer()
        }
        binding.btnNowPlayPause.bindPressFeedback(PressFeedback.Style.ICON)
        binding.nowPlayingBar.setOnClickListener {
            // Keep focus on radio list; dock is control-only.
        }

        lifecycleScope.launch {
            PlaybackCoordinator.currentSong.collectLatest { song ->
                playingId = song?.id?.takeIf { it.startsWith(RADIO_ID_PREFIX) }
                adapter.setPlayingId(playingId)
                updateNowPlayingBar(song?.name)
                refreshPlayingUiFromPlayer()
            }
        }

        rebuildChips()
        loadStations(forceRefresh = false)
    }

    override fun onResume() {
        super.onResume()
        recentStations = recentStore.load()
        if (selectedChip == RadioRegionHelper.RECENT) applyFilter()
        refreshPlayingUiFromPlayer()
    }

    private fun loadStations(forceRefresh: Boolean) {
        loadJob?.cancel()
        // Instant paint from in-memory/disk is handled inside loadStations; only spin when empty.
        val showCenterProgress = allStations.isEmpty() && !forceRefresh
        if (showCenterProgress) {
            binding.progress.isVisible = true
            binding.emptyState.isVisible = false
        }
        if (forceRefresh) {
            binding.swipeRefresh.isRefreshing = true
        }
        loadJob = lifecycleScope.launch {
            val result = RadioApiClient.loadStations(
                context = this@RadioActivity,
                forceRefresh = forceRefresh
            )
            binding.progress.isVisible = false
            binding.swipeRefresh.isRefreshing = false
            result.onSuccess { loaded ->
                allStations = loaded.stations
                rebuildChips()
                applyFilter()
                when {
                    forceRefresh && !loaded.fromCache -> {
                        Toast.makeText(
                            this@RadioActivity,
                            getString(R.string.radio_refreshed),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                    forceRefresh && loaded.fromCache -> {
                        // Network failed; repository fell back to disk/memory.
                        Toast.makeText(
                            this@RadioActivity,
                            getString(R.string.radio_refresh_fallback),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            }.onFailure { e ->
                if (allStations.isEmpty()) {
                    adapter.submitList(emptyList())
                    showEmpty(
                        message = e.message ?: getString(R.string.radio_load_failed),
                        showRetry = true
                    )
                } else {
                    Toast.makeText(
                        this@RadioActivity,
                        e.message ?: getString(R.string.radio_load_failed),
                        Toast.LENGTH_SHORT
                    ).show()
                    applyFilter()
                }
            }
        }
    }

    private fun rebuildChips() {
        val labels = RadioRegionHelper.buildChipLabels(
            stations = allStations,
            hasRecent = recentStations.isNotEmpty()
        )
        if (selectedChip !in labels) {
            selectedChip = RadioRegionHelper.ALL
        }
        binding.chipGroup.removeAllViews()
        labels.forEach { label ->
            val chip = Chip(this, null, com.google.android.material.R.attr.chipStyle).apply {
                text = label
                isCheckable = true
                isChecked = label == selectedChip
                isClickable = true
                setOnClickListener {
                    selectedChip = label
                    applyFilter()
                }
            }
            binding.chipGroup.addView(chip)
        }
        binding.chipScroll.isVisible = labels.size > 1 || allStations.isNotEmpty()
    }

    private fun applyFilter() {
        val q = binding.etSearch.text?.toString().orEmpty().trim()
        val base = when (selectedChip) {
            RadioRegionHelper.ALL -> allStations
            RadioRegionHelper.RECENT -> recentStations
            else -> allStations.filter { RadioRegionHelper.regionOf(it) == selectedChip }
        }
        val filtered = if (q.isBlank()) {
            base
        } else {
            base.filter { it.name.contains(q, ignoreCase = true) }
        }
        adapter.submitList(filtered)
        updateSubtitle(filtered.size)

        when {
            filtered.isNotEmpty() -> {
                binding.emptyState.isVisible = false
                binding.btnRetry.isVisible = false
            }
            allStations.isEmpty() -> {
                showEmpty(getString(R.string.radio_empty), showRetry = true)
            }
            selectedChip == RadioRegionHelper.RECENT -> {
                showEmpty(getString(R.string.radio_recent_empty), showRetry = false)
            }
            q.isNotBlank() -> {
                showEmpty(getString(R.string.radio_search_empty), showRetry = false)
            }
            else -> {
                showEmpty(getString(R.string.radio_filter_empty), showRetry = false)
            }
        }
    }

    private fun showEmpty(message: String, showRetry: Boolean) {
        binding.emptyState.isVisible = true
        binding.tvEmpty.text = message
        binding.btnRetry.isVisible = showRetry
    }

    private fun updateSubtitle(visibleCount: Int) {
        binding.tvSubtitle.text = when {
            allStations.isEmpty() -> getString(R.string.tools_radio_subtitle)
            visibleCount == allStations.size && selectedChip == RadioRegionHelper.ALL ->
                getString(R.string.radio_count_all, allStations.size)
            else -> getString(R.string.radio_count_filtered, visibleCount, allStations.size)
        }
    }

    private fun onStationClick(station: RadioStation) {
        val id = station.toSongId()
        if (id == playingId) {
            PlaybackCoordinator.togglePlayPause()
            refreshPlayingUiFromPlayer()
            return
        }
        playStation(station)
    }

    private fun playStation(station: RadioStation) {
        val song = station.toSong()
        PlaybackService.start(this)
        PlaybackCoordinator.playSong(song)
        recentStore.remember(station)
        recentStations = recentStore.load()
        rebuildChips()
        if (selectedChip == RadioRegionHelper.RECENT) applyFilter()
        Toast.makeText(this, getString(R.string.radio_playing, station.name), Toast.LENGTH_SHORT).show()
        updateNowPlayingBar(station.name)
        isRadioPlaying = true
        binding.btnNowPlayPause.setImageResource(R.drawable.ic_pause_24)
    }

    private fun updateNowPlayingBar(name: String?) {
        val show = playingId != null
        binding.nowPlayingBar.isVisible = show
        if (show) {
            binding.tvNowPlayingName.text = name.orEmpty().ifBlank {
                getString(R.string.tools_radio_title)
            }
        }
    }

    private fun refreshPlayingUiFromPlayer() {
        val player = PlaybackCoordinator.playerOrNull()
        val playing = player != null && (player.isPlaying || player.playWhenReady) && playingId != null
        isRadioPlaying = playing
        binding.btnNowPlayPause.setImageResource(
            if (playing) R.drawable.ic_pause_24 else R.drawable.ic_play_24
        )
        adapter.setPlayingActive(playing)
    }

    private fun hideKeyboard() {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(binding.etSearch.windowToken, 0)
        binding.etSearch.clearFocus()
    }

    private class StationAdapter(
        private val onClick: (RadioStation) -> Unit
    ) : ListAdapter<RadioStation, StationAdapter.VH>(Diff) {

        private var playingId: String? = null
        private var playingActive: Boolean = false

        fun setPlayingId(id: String?) {
            if (playingId == id) return
            val old = playingId
            playingId = id
            notifyPlayingChanged(old)
            notifyPlayingChanged(id)
        }

        fun setPlayingActive(active: Boolean) {
            if (playingActive == active) return
            playingActive = active
            notifyPlayingChanged(playingId)
        }

        private fun notifyPlayingChanged(id: String?) {
            if (id == null) return
            val idx = currentList.indexOfFirst { it.toSongId() == id }
            if (idx >= 0) notifyItemChanged(idx, PAYLOAD_PLAYING)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val binding = ItemRadioStationBinding.inflate(
                LayoutInflater.from(parent.context),
                parent,
                false
            )
            return VH(binding)
        }

        override fun onBindViewHolder(holder: VH, position: Int) {
            holder.bind(getItem(position), playingId, playingActive, onClick)
        }

        override fun onBindViewHolder(holder: VH, position: Int, payloads: MutableList<Any>) {
            if (payloads.contains(PAYLOAD_PLAYING)) {
                holder.bindPlaying(getItem(position), playingId, playingActive)
            } else {
                super.onBindViewHolder(holder, position, payloads)
            }
        }

        class VH(
            private val binding: ItemRadioStationBinding
        ) : RecyclerView.ViewHolder(binding.root) {
            fun bind(
                station: RadioStation,
                playingId: String?,
                playingActive: Boolean,
                onClick: (RadioStation) -> Unit
            ) {
                binding.tvName.text = station.name
                binding.tvAvatar.text = RadioRegionHelper.avatarLetter(station.name)
                val region = RadioRegionHelper.regionOf(station)
                binding.root.bindPressFeedback(PressFeedback.Style.ROW)
                binding.root.setOnClickListener { onClick(station) }
                bindPlaying(station, playingId, playingActive, region)
            }

            fun bindPlaying(
                station: RadioStation,
                playingId: String?,
                playingActive: Boolean,
                region: String = RadioRegionHelper.regionOf(station)
            ) {
                val id = station.toSongId()
                val playing = id == playingId
                val ctx = binding.root.context
                val primary = ctx.resolveThemeColor(R.attr.brandPrimary)
                val normal = ctx.resolveThemeColor(R.attr.textPrimary)
                val secondary = ctx.resolveThemeColor(R.attr.textSecondary)

                binding.tvName.setTextColor(if (playing) primary else normal)
                binding.ivPlaying.isVisible = playing
                binding.playingDot.isVisible = playing && playingActive
                binding.tvLiveBadge.isVisible = playing

                binding.tvMeta.text = when {
                    playing && playingActive -> ctx.getString(R.string.radio_now_playing)
                    playing -> ctx.getString(R.string.radio_paused)
                    region != RadioRegionHelper.OTHER ->
                        ctx.getString(R.string.radio_meta_region, region)
                    else -> ctx.getString(R.string.radio_tap_to_play)
                }
                binding.tvMeta.setTextColor(if (playing) primary else secondary)
            }
        }

        private object Diff : DiffUtil.ItemCallback<RadioStation>() {
            override fun areItemsTheSame(a: RadioStation, b: RadioStation): Boolean =
                a.playUrl == b.playUrl

            override fun areContentsTheSame(a: RadioStation, b: RadioStation): Boolean = a == b
        }

        companion object {
            private const val PAYLOAD_PLAYING = "playing"
        }
    }

    companion object {
        const val RADIO_ID_PREFIX = "radio:"

        fun intent(context: Context): Intent = Intent(context, RadioActivity::class.java)

        fun RadioStation.toSongId(): String =
            RADIO_ID_PREFIX + name.hashCode().toUInt().toString(16) + ":" +
                playUrl.hashCode().toUInt().toString(16)

        fun RadioStation.toSong(): com.music.player.data.model.Song {
            val id = toSongId()
            return com.music.player.data.model.Song(
                id = id,
                name = name,
                artists = listOf(Artist(id = "radio", name = "广播电台")),
                album = Album(id = "radio", name = "网络电台", picUrl = ""),
                duration = 0L,
                url = playUrl,
                source = "radio"
            )
        }
    }
}
