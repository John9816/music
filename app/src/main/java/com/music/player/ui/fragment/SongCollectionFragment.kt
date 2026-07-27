package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.activity.AiDrawActivity
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongCollectionHeaderHelper
import com.music.player.ui.util.SongOptionsHelper
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.optimizeVerticalScrolling
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel

class SongCollectionFragment : Fragment() {

    enum class Mode { LIKED, HISTORY, PLAYLIST }

    companion object {
        private const val ARG_MODE = "mode"
        private const val ARG_PLAYLIST_ID = "playlist_id"
        private const val ARG_PLAYLIST_NAME = "playlist_name"

        fun newLiked(): SongCollectionFragment = SongCollectionFragment().apply {
            arguments = Bundle().apply { putString(ARG_MODE, Mode.LIKED.name) }
        }

        fun newHistory(): SongCollectionFragment = SongCollectionFragment().apply {
            arguments = Bundle().apply { putString(ARG_MODE, Mode.HISTORY.name) }
        }

        fun newPlaylist(playlistId: String, playlistName: String): SongCollectionFragment =
            SongCollectionFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_MODE, Mode.PLAYLIST.name)
                    putString(ARG_PLAYLIST_ID, playlistId)
                    putString(ARG_PLAYLIST_NAME, playlistName)
                }
            }
    }

    private var _binding: FragmentSongCollectionBinding? = null
    private val binding: FragmentSongCollectionBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var songAdapter: SongAdapter

    private val mode: Mode
        get() = (arguments?.getString(ARG_MODE) ?: Mode.LIKED.name).let { Mode.valueOf(it) }

    private val playlistId: String
        get() = arguments?.getString(ARG_PLAYLIST_ID).orEmpty()

    private val playlistName: String
        get() = arguments?.getString(ARG_PLAYLIST_NAME).orEmpty()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentSongCollectionBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        binding.tvHeaderEyebrow.text = when (mode) {
            Mode.LIKED -> getString(R.string.collection_mode_liked)
            Mode.HISTORY -> getString(R.string.collection_mode_history)
            Mode.PLAYLIST -> getString(R.string.collection_mode_playlist)
        }
        val headerTitle = when (mode) {
            Mode.LIKED -> getString(R.string.profile_liked_title)
            Mode.HISTORY -> getString(R.string.profile_history_title)
            Mode.PLAYLIST -> playlistName.ifBlank { getString(R.string.user_playlist_title) }
        }
        binding.tvHeaderDescription.text = when (mode) {
            Mode.LIKED -> getString(R.string.favorites_subtitle)
            Mode.HISTORY -> getString(R.string.history_subtitle)
            Mode.PLAYLIST -> getString(R.string.user_playlist_loading)
        }
        binding.tvCollectionMode.text = when (mode) {
            Mode.LIKED -> getString(R.string.collection_mode_liked)
            Mode.HISTORY -> getString(R.string.collection_mode_history)
            Mode.PLAYLIST -> getString(R.string.collection_mode_playlist)
        }
        binding.tvHeaderDescription.visibility = View.VISIBLE
        binding.tvHeaderPlayCount.visibility = View.GONE
        binding.ivHeaderOverlay.visibility = View.VISIBLE
        binding.ivHeaderOverlay.setImageResource(
            when (mode) {
                Mode.LIKED -> R.drawable.ic_favorite_24
                Mode.HISTORY -> R.drawable.ic_play_24
                Mode.PLAYLIST -> R.drawable.ic_playlist_24
            }
        )
        SongCollectionHeaderHelper.setup(this, binding, headerTitle)

        songAdapter = SongAdapter(
            // NetEase/QQ style: tap a row keeps the full list as play context.
            onSongClick = { song ->
                val songs = songAdapter.currentList
                if (songs.isNotEmpty()) {
                    musicViewModel.playFromList(songs, song)
                } else {
                    musicViewModel.playStandaloneSong(song)
                }
            },
            onMoreClick = { _, song ->
                when (mode) {
                    Mode.LIKED -> showLikedSongMenu(song)
                    Mode.HISTORY -> showHistorySongMenu(song)
                    Mode.PLAYLIST -> showPlaylistSongMenu(song)
                }
            }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            optimizeVerticalScrolling()
        }

        binding.btnPlayAll.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.btnPlayAll.setOnClickListener { playAll() }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            songAdapter.setCurrentPlayingId(song?.id)
        }

        libraryViewModel.favorites.observe(viewLifecycleOwner) { songs ->
            if (mode != Mode.LIKED) return@observe
            renderSongs(songs, emptyRes = R.string.profile_liked_empty)
        }

        libraryViewModel.history.observe(viewLifecycleOwner) { songs ->
            if (mode != Mode.HISTORY) return@observe
            renderSongs(songs, emptyRes = R.string.profile_history_empty)
        }

        libraryViewModel.playlistSongs.observe(viewLifecycleOwner) { songs ->
            if (mode != Mode.PLAYLIST) return@observe
            renderSongs(songs, emptyRes = R.string.song_list_empty_playlist)
            syncPlaylistHeader(songs)
        }

        libraryViewModel.playlists.observe(viewLifecycleOwner) { playlists ->
            if (mode != Mode.PLAYLIST) return@observe
            syncPlaylistHeader(songAdapter.currentList, playlists.firstOrNull { it.id == playlistId })
            updateRemoteSyncMenu()
            // Once playlist meta is available, auto-sync remote sources (throttled in VM).
            libraryViewModel.maybeAutoSyncRemotePlaylist(playlistId)
        }

        libraryViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            updateLoadingState(loading)
        }

        if (mode == Mode.PLAYLIST) {
            installRemoteSyncMenu()
        }

        refreshCurrentCollection()
    }

    private fun installRemoteSyncMenu() {
        val toolbar = binding.toolbarCollapsed
        toolbar.menu.clear()
        toolbar.inflateMenu(R.menu.menu_user_playlist_detail)
        toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_ai_cover -> {
                    openAiCover()
                    true
                }
                R.id.action_sync_playlist -> {
                    libraryViewModel.syncRemotePlaylist(playlistId, silent = false)
                    true
                }
                else -> false
            }
        }
        updateRemoteSyncMenu()
    }

    private fun updateRemoteSyncMenu() {
        if (mode != Mode.PLAYLIST || _binding == null) return
        val menu: Menu = binding.toolbarCollapsed.menu
        val item: MenuItem? = menu.findItem(R.id.action_sync_playlist)
        item?.isVisible = libraryViewModel.isRemotePlaylist(playlistId)
        menu.findItem(R.id.action_ai_cover)?.isVisible = true
    }

    private fun openAiCover() {
        val meta = libraryViewModel.playlists.value.orEmpty().firstOrNull { it.id == playlistId }
        val ref = meta?.coverUrl
            ?: songAdapter.currentList.firstOrNull()?.album?.picUrl?.takeIf { it.isNotBlank() }
        startActivity(
            AiDrawActivity.intent(
                context = requireContext(),
                playlistId = playlistId,
                playlistName = playlistName.ifBlank { meta?.name.orEmpty() },
                ref1 = ref
            )
        )
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun renderSongs(songs: List<Song>, emptyRes: Int) {
        songAdapter.submitList(songs) {
            if (_binding != null) {
                songAdapter.setCurrentPlayingId(musicViewModel.currentSong.value?.id)
            }
        }
        binding.tvCollectionCount.text = getString(R.string.collection_count_value, songs.size)
        binding.tvEmpty.setText(emptyRes)
        binding.layoutSkeleton.visibility = View.GONE
        binding.tvEmpty.visibility = if (songs.isEmpty()) View.VISIBLE else View.GONE
        binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
        binding.btnPlayAll.isEnabled = songs.isNotEmpty()
        if (mode != Mode.PLAYLIST) {
            SongCollectionHeaderHelper.loadCovers(
                binding,
                songs.firstOrNull()?.album?.picUrl
            )
            binding.ivHeaderOverlay.visibility =
                if (songs.firstOrNull()?.album?.picUrl.isNullOrBlank()) View.VISIBLE else View.GONE
        }
    }

    private fun updateLoadingState(loading: Boolean) {
        if (_binding == null) return
        val showSkeleton = loading && songAdapter.currentList.isEmpty()
        binding.layoutSkeleton.visibility = if (showSkeleton) View.VISIBLE else View.GONE
        if (showSkeleton) {
            binding.recyclerView.visibility = View.GONE
            binding.tvEmpty.visibility = View.GONE
        }
    }

    private fun refreshCurrentCollection() {
        // Soft revalidate: use memory/disk first; network only when TTL expired.
        // User pull-to-refresh can pass force later if we add a dedicated swipe flag.
        when (mode) {
            Mode.LIKED -> libraryViewModel.refreshFavorites(silent = true, forceRefresh = false)
            Mode.HISTORY -> libraryViewModel.refreshHistory(silent = true, forceRefresh = false)
            Mode.PLAYLIST -> {
                libraryViewModel.refreshPlaylists(silent = true, forceRefresh = false)
                libraryViewModel.loadPlaylistSongs(playlistId, forceRefresh = false)
                // Auto-sync if meta already in memory (observer also covers late list load).
                libraryViewModel.maybeAutoSyncRemotePlaylist(playlistId)
            }
        }
    }

    private fun syncPlaylistHeader(
        songs: List<Song>,
        playlist: UserPlaylist? = libraryViewModel.playlists.value.orEmpty().firstOrNull { it.id == playlistId }
    ) {
        SongCollectionHeaderHelper.setTitle(
            binding,
            playlist?.name?.takeIf { it.isNotBlank() }
                ?: playlistName.ifBlank { getString(R.string.user_playlist_title) }
        )

        val description = playlist?.description
            ?.replace(Regex("\\s+"), " ")
            ?.trim()
            .orEmpty()
        val headerDescription = when {
            description.isNotBlank() -> description
            songs.isNotEmpty() -> getString(R.string.songs_loaded_count, songs.size)
            else -> getString(R.string.collection_playlist_description_fallback)
        }
        binding.tvHeaderDescription.text = headerDescription
        binding.tvHeaderDescription.visibility = View.VISIBLE
        val totalSongCount = playlist?.trackCount?.takeIf { it > 0 } ?: songs.size
        binding.tvCollectionCount.text =
            getString(R.string.collection_count_value, totalSongCount)

        binding.tvCollectionMode.text = when {
            playlist?.isPublic == true -> getString(R.string.collection_mode_public)
            playlist != null -> getString(R.string.collection_mode_private)
            else -> getString(R.string.collection_mode_playlist)
        }

        val cover = playlist?.coverUrl?.trim().takeUnless { it.isNullOrBlank() }
            ?: songs.firstOrNull()?.album?.picUrl
        SongCollectionHeaderHelper.loadCovers(binding, cover)
        binding.ivHeaderOverlay.visibility = if (cover.isNullOrBlank()) View.VISIBLE else View.GONE
    }

    private fun playAll() {
        val songs = songAdapter.currentList
        if (songs.isEmpty()) return
        musicViewModel.playFromList(songs, songs.first())
    }

    private fun showLikedSongMenu(song: Song) {
        val pinned = libraryViewModel.isPinnedFavorite(song.id)
        SongOptionsHelper.show(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = ::showAddToPlaylistDialog,
            config = SongOptionsHelper.Config(
                includePlayNext = true,
                includeAddToQueue = true,
                isFavorite = true,
                onToggleFavorite = { libraryViewModel.setFavorite(song, false) },
                favoriteLabels = R.string.action_unlike to R.string.action_like,
                extraTrailing = listOf(
                    SongOption(getString(if (pinned) R.string.action_unpin else R.string.action_pin_to_top)) {
                        libraryViewModel.togglePinFavorite(song.id)
                    }
                )
            )
        )
    }

    private fun showHistorySongMenu(song: Song) {
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        val pinned = libraryViewModel.isPinnedHistory(song.id)
        SongOptionsHelper.show(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = ::showAddToPlaylistDialog,
            config = SongOptionsHelper.Config(
                isFavorite = isFavorite,
                onToggleFavorite = { libraryViewModel.setFavorite(song, !isFavorite) },
                favoriteLabels = R.string.action_unlike to R.string.action_like,
                extraTrailing = listOf(
                    SongOption(getString(if (pinned) R.string.action_unpin else R.string.action_pin_to_top)) {
                        libraryViewModel.togglePinHistory(song.id)
                    },
                    SongOption(getString(R.string.action_delete_history_record)) {
                        libraryViewModel.deleteHistoryItem(song.id)
                    }
                )
            )
        )
    }

    private fun showPlaylistSongMenu(song: Song) {
        if (playlistId.isBlank()) return
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        SongOptionsHelper.show(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = ::showAddToPlaylistDialog,
            config = SongOptionsHelper.Config(
                isFavorite = isFavorite,
                onToggleFavorite = { libraryViewModel.setFavorite(song, !isFavorite) },
                favoriteLabels = R.string.action_unlike to R.string.action_like,
                extraTrailing = listOf(
                    SongOption(getString(R.string.action_remove_from_playlist)) {
                        libraryViewModel.removeSongFromPlaylist(playlistId, song.id)
                    }
                )
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
}
