package com.music.player.ui.fragment

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.AppBarLayout
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.MainActivity
import com.music.player.data.model.NewestAlbum
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentDiscoverBinding
import com.music.player.ui.adapter.HotSongAdapter
import com.music.player.ui.adapter.NewestAlbumBannerAdapter
import com.music.player.ui.adapter.SongAdapter
import com.music.player.data.api.NetworkRuntime
import com.music.player.data.settings.AppSettings
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.SongOptionsHelper
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.optimizeVerticalScrolling
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel

class DiscoverFragment : Fragment(), RootTabInteraction {

    private var _binding: FragmentDiscoverBinding? = null
    private val binding: FragmentDiscoverBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var songAdapter: SongAdapter
    private lateinit var weeklyHotAdapter: HotSongAdapter
    private lateinit var newestAlbumAdapter: NewestAlbumBannerAdapter

    private val newestAlbumSnapHelper = PagerSnapHelper()
    private val newestAlbumHandler = Handler(Looper.getMainLooper())
    private val newestAlbumIntervalMs = 4500L
    private val newestAlbumAutoScroll = object : Runnable {
        override fun run() {
            val binding = _binding ?: return
            val adapter = binding.rvNewestAlbums.adapter ?: return
            val count = adapter.itemCount
            if (count <= 1) return

            val lm = binding.rvNewestAlbums.layoutManager as? LinearLayoutManager ?: return
            val snapped = newestAlbumSnapHelper.findSnapView(lm) ?: return
            val current = lm.getPosition(snapped).coerceAtLeast(0)
            val next = (current + 1) % count
            binding.rvNewestAlbums.smoothScrollToPosition(next)

            newestAlbumHandler.postDelayed(this, newestAlbumIntervalMs)
        }
    }

    private var isMusicLoading = false
    private var isLibraryLoading = false
    private var isWeeklyHotLoading = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentDiscoverBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val ctx = requireContext()
        if (!NetworkRuntime.isNetworkAvailable() || AppSettings.isOfflineOnly(ctx)) {
            Toast.makeText(ctx, R.string.offline_network_banner, Toast.LENGTH_SHORT).show()
        }
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        binding.layoutHeroContent.applyStatusBarInsetPadding()
        binding.stickySongsHeader.applyStatusBarInsetPadding()
        setupRecyclerViews()
        setupObservers()
        setupInteractions()

        binding.tvSongListSubtitle.text = getString(R.string.daily_recommend_subtitle)
        updateSummaryChips(
            recommendCount = musicViewModel.dailyRecommend.value.orEmpty().size,
            weeklyCount = musicViewModel.weeklyHotSongs.value.orEmpty().size,
            albumCount = musicViewModel.newestAlbums.value.orEmpty().size
        )

        val daily = musicViewModel.dailyRecommend.value.orEmpty()
        if (daily.isNotEmpty()) {
            renderSongs(daily)
        }
        val weekly = musicViewModel.weeklyHotSongs.value.orEmpty()
        if (weekly.isNotEmpty()) {
            weeklyHotAdapter.submitList(weekly)
            updateSummaryChips(weeklyCount = weekly.size)
        }
        val albums = musicViewModel.newestAlbums.value.orEmpty()
        if (albums.isNotEmpty()) {
            newestAlbumAdapter.submitList(albums)
            updateSummaryChips(albumCount = albums.size)
            maybeStartNewestAlbumCarousel()
        }
        // Full discover warm: daily + weekly + newest albums (not daily-only).
        if (daily.isEmpty() || weekly.isEmpty() || albums.isEmpty()) {
            musicViewModel.prefetchDiscover(forceRefresh = false)
        }
    }

    override fun onResume() {
        super.onResume()
    }

    override fun onPause() {
        stopNewestAlbumCarousel()
        super.onPause()
    }

    override fun onDestroyView() {
        stopNewestAlbumCarousel()
        super.onDestroyView()
        _binding = null
    }

    override fun onTabReselected() {
        val binding = _binding ?: return
        binding.appBar.setExpanded(true, true)
        if (binding.recyclerView.canScrollVertically(-1)) {
            binding.recyclerView.smoothScrollToPosition(0)
            return
        }
        refreshContent(userInitiated = true)
    }

    override fun onMusicSourceChanged() {
        val binding = _binding ?: return
        binding.appBar.setExpanded(true, false)
        songAdapter.submitList(emptyList())
        weeklyHotAdapter.submitList(emptyList())
        newestAlbumAdapter.submitList(emptyList())
        stopNewestAlbumCarousel()
        syncEmptyState(forceEmpty = false)
        libraryViewModel.prefetch(forceRefresh = true)
        musicViewModel.prefetchDiscover(forceRefresh = true)
    }

    private fun setupRecyclerViews() {
        songAdapter = SongAdapter(
            // Daily recommend is a list context: keep queue from the tapped song onward.
            onSongClick = { song ->
                val songs = songAdapter.currentList
                if (songs.isNotEmpty()) {
                    musicViewModel.playFromList(songs, song)
                } else {
                    musicViewModel.playStandaloneSong(song)
                }
            },
            onSongLongClick = { song -> showSongActions(song) },
            onMoreClick = { _, song -> showDailyRecommendMenu(song) }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            optimizeVerticalScrolling()
        }

        weeklyHotAdapter = HotSongAdapter(
            onSongClick = { song ->
                val songs = weeklyHotAdapter.currentList
                if (songs.isNotEmpty()) {
                    musicViewModel.playFromList(songs, song)
                } else {
                    musicViewModel.playStandaloneSong(song)
                }
            },
            onSongLongClick = { song -> showSongActions(song) }
        )
        binding.rvWeeklyHot.layoutManager =
            LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
        binding.rvWeeklyHot.adapter = weeklyHotAdapter
        binding.rvWeeklyHot.setHasFixedSize(true)

        newestAlbumAdapter = NewestAlbumBannerAdapter(
            onAlbumClick = { album -> openNewestAlbum(album) }
        )
        binding.rvNewestAlbums.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
            adapter = newestAlbumAdapter
            setHasFixedSize(true)
        }
    }

    private fun setupInteractions() {
        binding.cardSongsSearch.bindPressFeedback(PressFeedback.Style.CARD)
        binding.btnPlayAllSongs.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.btnShuffleSongs.bindPressFeedback(PressFeedback.Style.ICON)
        binding.cardSongsSearch.setOnClickListener {
            (activity as? MainActivity)?.openSearchTab(focus = true)
        }
        binding.btnPlayAllSongs.setOnClickListener {
            val songs = songAdapter.currentList
            if (songs.isNotEmpty()) {
                musicViewModel.playFromList(songs, songs.first())
            }
        }
        binding.btnShuffleSongs.setOnClickListener {
            val songs = songAdapter.currentList.shuffled()
            if (songs.isNotEmpty()) {
                musicViewModel.playFromList(songs, songs.first())
            }
        }
        binding.appBar.addOnOffsetChangedListener(AppBarLayout.OnOffsetChangedListener { _, verticalOffset ->
            binding.stickySongsHeader.visibility = if (verticalOffset < 0) View.VISIBLE else View.GONE
        })
    }

    private fun setupObservers() {
        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            songAdapter.setCurrentPlayingId(song?.id)
        }
        musicViewModel.dailyRecommend.observe(viewLifecycleOwner) { songs ->
            renderSongs(songs)
            binding.tvSongListSubtitle.text = getString(R.string.recommend_loaded_count, songs.size)
            updateSummaryChips(recommendCount = songs.size)
        }

        musicViewModel.weeklyHotSongs.observe(viewLifecycleOwner) { songs ->
            weeklyHotAdapter.submitList(songs)
            updateSummaryChips(weeklyCount = songs.size)
            syncWeeklyHotCardVisibility()
        }

        musicViewModel.newestAlbums.observe(viewLifecycleOwner) { albums ->
            newestAlbumAdapter.submitList(albums)
            updateSummaryChips(albumCount = albums.size)
            if (albums.size > 1) {
                maybeStartNewestAlbumCarousel()
            } else {
                stopNewestAlbumCarousel()
            }
        }

        musicViewModel.weeklyHotLoading.observe(viewLifecycleOwner) { loading ->
            isWeeklyHotLoading = loading
            binding.pbWeeklyHot.visibility = if (loading) View.VISIBLE else View.GONE
            syncWeeklyHotCardVisibility()
        }

        // Content loading only — never PlaybackCoordinator stream prepare.
        musicViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            isMusicLoading = loading
            syncLoadingState()
            syncEmptyState()
        }

        libraryViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            isLibraryLoading = loading
            syncLoadingState()
        }

        musicViewModel.discoverError.observe(viewLifecycleOwner) { message ->
            syncContentError(message)
        }

        binding.btnContentRetry.setOnClickListener {
            musicViewModel.clearDiscoverError()
            refreshContent(userInitiated = true)
        }
    }

    private fun refreshContent(userInitiated: Boolean) {
        libraryViewModel.prefetch(forceRefresh = userInitiated)
        musicViewModel.prefetchDiscover(forceRefresh = userInitiated)
    }

    private fun maybeStartNewestAlbumCarousel() {
        stopNewestAlbumCarousel()
        val count = newestAlbumAdapter.itemCount
        if (count <= 1) return
        newestAlbumHandler.postDelayed(newestAlbumAutoScroll, newestAlbumIntervalMs)
    }

    private fun stopNewestAlbumCarousel() {
        newestAlbumHandler.removeCallbacks(newestAlbumAutoScroll)
    }

    private fun syncWeeklyHotCardVisibility() {
        val binding = _binding ?: return
        binding.cardWeeklyHot.visibility = View.VISIBLE
    }

    private fun updateSummaryChips(
        recommendCount: Int = songAdapter.currentList.size,
        weeklyCount: Int = weeklyHotAdapter.currentList.size,
        albumCount: Int = newestAlbumAdapter.currentList.size
    ) {
        val binding = _binding ?: return
        binding.tvRecommendSummary.text = getString(R.string.discover_summary_recommend_count, recommendCount)
        binding.tvWeeklySummary.text = getString(R.string.discover_summary_weekly_count, weeklyCount)
        binding.tvAlbumSummary.text = getString(R.string.discover_summary_album_count, albumCount)
    }

    private fun renderSongs(songs: List<Song>) {
        songAdapter.submitList(songs) {
            if (_binding != null) {
                songAdapter.setCurrentPlayingId(musicViewModel.currentSong.value?.id)
            }
        }
        syncEmptyState(songs.isEmpty())
    }

    private fun syncEmptyState(forceEmpty: Boolean = songAdapter.currentList.isEmpty()) {
        val anyLoading = isMusicLoading || isLibraryLoading
        val hasError = !musicViewModel.discoverError.value.isNullOrBlank()
        val showEmpty = !anyLoading && !hasError && forceEmpty
        binding.layoutEmptyState.visibility = if (showEmpty) View.VISIBLE else View.GONE
        binding.tvEmptyState.visibility = if (showEmpty) View.VISIBLE else View.GONE
        binding.tvEmptyState.text = getString(R.string.song_list_empty_recommend)
    }

    private fun syncContentError(message: String?) {
        val binding = _binding ?: return
        val anyLoading = isMusicLoading || isLibraryLoading
        val hasList = songAdapter.currentList.isNotEmpty()
        val showError = !message.isNullOrBlank() && !anyLoading && !hasList
        binding.layoutContentError.visibility = if (showError) View.VISIBLE else View.GONE
        if (showError) {
            binding.tvContentError.text = message
            binding.layoutEmptyState.visibility = View.GONE
        } else if (!message.isNullOrBlank() && hasList) {
            // Soft failure while list still usable — keep list, no full-page error.
            binding.layoutContentError.visibility = View.GONE
        }
        syncEmptyState()
    }

    private fun syncLoadingState() {
        val anyLoading = isMusicLoading || isLibraryLoading
        binding.progressBar.visibility = if (anyLoading) View.VISIBLE else View.GONE
        if (anyLoading) {
            binding.layoutContentError.visibility = View.GONE
        }
    }

    private fun showSongActions(song: Song) {
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        SongOptionsHelper.showStandard(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = ::showAddToPlaylistDialog,
            isFavorite = isFavorite,
            onToggleFavorite = { libraryViewModel.setFavorite(song, !isFavorite) },
            includeDownload = true
        )
    }

    private fun showDailyRecommendMenu(song: Song) {
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        SongOptionsHelper.show(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = ::showAddToPlaylistDialog,
            config = SongOptionsHelper.Config(
                includeAddToQueue = false,
                isFavorite = isFavorite,
                onToggleFavorite = { libraryViewModel.setFavorite(song, !isFavorite) },
                favoriteLabels = R.string.action_unlike to R.string.action_like
            )
        )
    }

    private fun showAddToPlaylistDialog(song: Song) {
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

    private fun startSongDownload(song: Song) {
        SongDownloader.download(requireContext(), musicViewModel, song)
    }

    private fun openNewestAlbum(album: NewestAlbum) {
        (activity as? MainActivity)?.pushDetail(
            AlbumSongsFragment.newInstance(
                albumId = album.album.id,
                albumName = album.album.name,
                artistNames = album.artistNames,
                coverUrl = album.album.picUrl
            )
        )
    }
}
