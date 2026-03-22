package com.music.player.ui.fragment

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.appcompat.widget.PopupMenu
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.AppBarLayout
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentDiscoverBinding
import com.music.player.ui.adapter.HotSongAdapter
import com.music.player.ui.adapter.NewestAlbumBannerAdapter
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.resolveThemeColor
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
    private var isUserRefreshing = false
    private var appBarVerticalOffset = 0
    private var awaitingRecommendRefresh = false
    private var awaitingWeeklyHotRefresh = false
    private var awaitingNewestAlbumRefresh = false

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
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        setupRecyclerViews()
        setupObservers()
        setupInteractions()

        binding.tvSongListSubtitle.text = getString(R.string.daily_recommend_subtitle)

        val shouldWarmDiscover = musicViewModel.dailyRecommend.value.isNullOrEmpty() ||
            musicViewModel.weeklyHotSongs.value.isNullOrEmpty() ||
            musicViewModel.newestAlbums.value.isNullOrEmpty()

        if (shouldWarmDiscover) {
            musicViewModel.prefetchDiscover(limit = 10)
        } else {
            renderSongs(musicViewModel.dailyRecommend.value.orEmpty())
            weeklyHotAdapter.submitList(musicViewModel.weeklyHotSongs.value.orEmpty())
            newestAlbumAdapter.submitList(musicViewModel.newestAlbums.value.orEmpty())
            binding.rvNewestAlbums.visibility =
                if (newestAlbumAdapter.currentList.isEmpty()) View.GONE else View.VISIBLE
            syncWeeklyHotCardVisibility()
            maybeStartNewestAlbumCarousel()
        }
    }

    override fun onResume() {
        super.onResume()
        maybeStartNewestAlbumCarousel()
    }

    override fun onPause() {
        super.onPause()
        stopNewestAlbumCarousel()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        stopNewestAlbumCarousel()
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

    private fun setupRecyclerViews() {
        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onSongLongClick = { song -> showSongActions(song) },
            onMoreClick = { anchor, song -> showDailyRecommendMenu(anchor, song) }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            setHasFixedSize(true)
        }

        weeklyHotAdapter = HotSongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onSongLongClick = { song -> showSongActions(song) }
        )
        binding.rvWeeklyHot.layoutManager =
            LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
        binding.rvWeeklyHot.adapter = weeklyHotAdapter
        binding.rvWeeklyHot.setHasFixedSize(true)

        newestAlbumAdapter = NewestAlbumBannerAdapter()
        binding.rvNewestAlbums.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
            adapter = newestAlbumAdapter
            setHasFixedSize(true)
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                    if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                        maybeStartNewestAlbumCarousel()
                    } else {
                        stopNewestAlbumCarousel()
                    }
                }
            })
        }
        newestAlbumSnapHelper.attachToRecyclerView(binding.rvNewestAlbums)
    }

    private fun setupInteractions() {
        binding.swipeRefresh.setColorSchemeColors(requireContext().resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setDistanceToTriggerSync(
            resources.getDimensionPixelSize(R.dimen.spacing_xxl)
        )
        binding.swipeRefresh.setOnChildScrollUpCallback { _, _ ->
            shouldBlockSwipeRefresh()
        }
        binding.swipeRefresh.setOnRefreshListener {
            refreshContent(userInitiated = true)
        }
        binding.appBar.addOnOffsetChangedListener(AppBarLayout.OnOffsetChangedListener { _, verticalOffset ->
            appBarVerticalOffset = verticalOffset
        })
    }

    private fun setupObservers() {
        musicViewModel.dailyRecommend.observe(viewLifecycleOwner) { songs ->
            renderSongs(songs)
            binding.tvSongListSubtitle.text = getString(R.string.recommend_loaded_count, songs.size)
            awaitingRecommendRefresh = false
            syncRefreshState()
        }

        musicViewModel.weeklyHotSongs.observe(viewLifecycleOwner) { songs ->
            weeklyHotAdapter.submitList(songs)
            syncWeeklyHotCardVisibility()
            awaitingWeeklyHotRefresh = false
            syncRefreshState()
        }

        musicViewModel.newestAlbums.observe(viewLifecycleOwner) { albums ->
            newestAlbumAdapter.submitList(albums)
            binding.rvNewestAlbums.visibility = if (albums.isEmpty()) View.GONE else View.VISIBLE
            syncWeeklyHotCardVisibility()
            maybeStartNewestAlbumCarousel()
            awaitingNewestAlbumRefresh = false
            syncRefreshState()
        }

        musicViewModel.weeklyHotLoading.observe(viewLifecycleOwner) { loading ->
            isWeeklyHotLoading = loading
            binding.pbWeeklyHot.visibility = if (loading) View.VISIBLE else View.GONE
            syncWeeklyHotCardVisibility()
        }

        musicViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            isMusicLoading = loading
            syncLoadingState()
            syncEmptyState()
        }

        libraryViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            isLibraryLoading = loading
            syncLoadingState()
        }
    }

    private fun refreshContent(userInitiated: Boolean) {
        if (userInitiated) {
            isUserRefreshing = true
            awaitingRecommendRefresh = true
            awaitingWeeklyHotRefresh = true
            awaitingNewestAlbumRefresh = true
            binding.swipeRefresh.isRefreshing = true
            binding.swipeRefresh.postDelayed({
                if (_binding != null && isUserRefreshing) {
                    stopRefreshIndicator()
                }
            }, 3000L)
        }
        libraryViewModel.prefetch(forceRefresh = userInitiated)
        musicViewModel.prefetchDiscover(limit = 10, forceRefresh = userInitiated)
    }

    private fun maybeStartNewestAlbumCarousel() {
        val binding = _binding ?: return
        if (!isResumed) return
        if (binding.rvNewestAlbums.visibility != View.VISIBLE) return
        if ((binding.rvNewestAlbums.adapter?.itemCount ?: 0) <= 1) return
        newestAlbumHandler.removeCallbacks(newestAlbumAutoScroll)
        newestAlbumHandler.postDelayed(newestAlbumAutoScroll, newestAlbumIntervalMs)
    }

    private fun stopNewestAlbumCarousel() {
        newestAlbumHandler.removeCallbacks(newestAlbumAutoScroll)
    }

    private fun syncWeeklyHotCardVisibility() {
        val binding = _binding ?: return
        val hasWeeklyHot = weeklyHotAdapter.currentList.isNotEmpty()
        val hasNewestAlbums = newestAlbumAdapter.currentList.isNotEmpty()
        binding.cardWeeklyHot.visibility =
            if (isWeeklyHotLoading || hasWeeklyHot || hasNewestAlbums) View.VISIBLE else View.GONE
    }

    private fun renderSongs(songs: List<Song>) {
        songAdapter.submitList(songs)
        syncEmptyState(songs.isEmpty())
    }

    private fun syncEmptyState(forceEmpty: Boolean = songAdapter.currentList.isEmpty()) {
        val anyLoading = isMusicLoading || isLibraryLoading
        binding.tvEmptyState.visibility = if (anyLoading || !forceEmpty) View.GONE else View.VISIBLE
        binding.tvEmptyState.text = getString(R.string.song_list_empty_recommend)
    }

    private fun syncLoadingState() {
        val anyLoading = isMusicLoading || isLibraryLoading
        binding.progressBar.visibility = if (anyLoading) View.VISIBLE else View.GONE
    }

    private fun syncRefreshState() {
        if (!isUserRefreshing) return
        if (awaitingRecommendRefresh || awaitingWeeklyHotRefresh || awaitingNewestAlbumRefresh) return
        stopRefreshIndicator()
    }

    private fun stopRefreshIndicator() {
        isUserRefreshing = false
        awaitingRecommendRefresh = false
        awaitingWeeklyHotRefresh = false
        awaitingNewestAlbumRefresh = false
        binding.swipeRefresh.isRefreshing = false
    }

    private fun shouldBlockSwipeRefresh(): Boolean {
        if (_binding == null) return true
        if (binding.swipeRefresh.isRefreshing) return false
        if (appBarVerticalOffset != 0) return true
        return binding.recyclerView.canScrollVertically(-1)
    }

    private fun showSongActions(song: Song) {
        val favoriteIds = libraryViewModel.favoriteIds.value.orEmpty()
        val isFavorite = favoriteIds.contains(song.id)

        val items = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        items += getString(if (isFavorite) R.string.action_unfavorite else R.string.action_favorite)
        actions += { libraryViewModel.setFavorite(song, !isFavorite) }

        items += getString(R.string.action_add_to_playlist)
        actions += { showAddToPlaylistDialog(song) }

        items += getString(R.string.action_play_next)
        actions += {
            musicViewModel.enqueueNext(song)
            Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue_next), Toast.LENGTH_SHORT).show()
        }

        items += getString(R.string.action_add_to_queue)
        actions += {
            musicViewModel.enqueue(song)
            Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue), Toast.LENGTH_SHORT).show()
        }

        MaterialAlertDialogBuilder(requireContext())
            .setTitle(song.name)
            .setItems(items.toTypedArray()) { _, which -> actions[which].invoke() }
            .show()
    }

    private fun showDailyRecommendMenu(anchor: View, song: Song) {
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        val popup = PopupMenu(requireContext(), anchor).apply {
            menuInflater.inflate(R.menu.song_discover_more_menu, menu)
        }

        popup.menu.findItem(R.id.action_like)?.title =
            getString(if (isFavorite) R.string.action_unlike else R.string.action_like)

        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_play_next -> {
                    musicViewModel.enqueueNext(song)
                    Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue_next), Toast.LENGTH_SHORT).show()
                    true
                }

                R.id.action_like -> {
                    libraryViewModel.setFavorite(song, !isFavorite)
                    true
                }

                R.id.action_download_song -> {
                    startSongDownload(song)
                    true
                }

                else -> false
            }
        }

        popup.show()
    }

    private fun startSongDownload(song: Song) {
        musicViewModel.resolveSongUrl(song) { result ->
            val context = context ?: return@resolveSongUrl
            result
                .onSuccess { url ->
                    if (url.isBlank()) {
                        Toast.makeText(context, getString(R.string.msg_song_download_unavailable), Toast.LENGTH_SHORT).show()
                        return@onSuccess
                    }
                    enqueueSongDownload(song, url)
                }
                .onFailure {
                    Toast.makeText(context, getString(R.string.msg_song_download_unavailable), Toast.LENGTH_SHORT).show()
                }
        }
    }

    private fun enqueueSongDownload(song: Song, url: String) {
        val context = context ?: return
        val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
        if (downloadManager == null) {
            Toast.makeText(context, getString(R.string.msg_song_download_failed), Toast.LENGTH_SHORT).show()
            return
        }

        runCatching {
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setTitle(song.name)
                setDescription(
                    getString(
                        R.string.download_song_description,
                        song.name,
                        song.artists.joinToString(", ") { it.name }
                    )
                )
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
                setMimeType("audio/mpeg")
                setDestinationInExternalPublicDir(
                    Environment.DIRECTORY_MUSIC,
                    "Duck Music/${buildDownloadFileName(song)}"
                )
            }
            downloadManager.enqueue(request)
        }.onSuccess {
            Toast.makeText(context, getString(R.string.msg_song_download_started), Toast.LENGTH_SHORT).show()
        }.onFailure {
            Toast.makeText(context, getString(R.string.msg_song_download_failed), Toast.LENGTH_SHORT).show()
        }
    }

    private fun buildDownloadFileName(song: Song): String {
        val artistNames = song.artists.joinToString(", ") { it.name }.ifBlank { "Unknown Artist" }
        val rawName = "${song.name} - $artistNames.mp3"
        return rawName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
    }

    private fun showAddToPlaylistDialog(song: Song) {
        val playlists = libraryViewModel.playlists.value.orEmpty()
        if (playlists.isEmpty()) {
            Toast.makeText(requireContext(), getString(R.string.user_playlist_create_first), Toast.LENGTH_SHORT).show()
            showCreatePlaylistDialog()
            return
        }

        val names = playlists.map { it.name }.toTypedArray()
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.user_playlist_pick_title)
            .setItems(names) { _, which ->
                libraryViewModel.addSongToPlaylist(playlists[which].id, song)
            }
            .show()
    }

    private fun showCreatePlaylistDialog() {
        val dialogView = layoutInflater.inflate(R.layout.dialog_create_playlist, null)
        val nameInput =
            dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etPlaylistName)
        val descInput =
            dialogView.findViewById<com.google.android.material.textfield.TextInputEditText>(R.id.etPlaylistDesc)

        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.user_playlist_create_title)
            .setView(dialogView)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.user_playlist_create_confirm) { _, _ ->
                val name = nameInput.text?.toString()?.trim().orEmpty()
                val desc = descInput.text?.toString()?.trim().orEmpty()
                if (name.isBlank()) {
                    Toast.makeText(requireContext(), getString(R.string.user_playlist_name_required), Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                libraryViewModel.createPlaylist(name, desc)
            }
            .show()
    }
}
