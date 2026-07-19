package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.resolveThemeColorStateList
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
    private var headerCollapsed = false
    private var headerDescriptionVisibility = View.VISIBLE
    private var headerOverlayVisibility = View.VISIBLE

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
        binding.tvHeaderTitle.text = when (mode) {
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
        binding.ivHeaderOverlay.setImageResource(
            when (mode) {
                Mode.LIKED -> R.drawable.ic_favorite_24
                Mode.HISTORY -> R.drawable.ic_play_24
                Mode.PLAYLIST -> R.drawable.ic_playlist_24
            }
        )

        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onMoreClick = { anchor, song ->
                when (mode) {
                    Mode.LIKED -> showLikedSongMenu(anchor, song)
                    Mode.HISTORY -> showHistorySongMenu(anchor, song)
                    Mode.PLAYLIST -> showPlaylistSongMenu(anchor, song)
                }
            }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            setHasFixedSize(true)
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    if (dy > 0 && !headerCollapsed) {
                        setHeaderCollapsed(true)
                    } else if (dy < 0 && !recyclerView.canScrollVertically(-1) && headerCollapsed) {
                        setHeaderCollapsed(false)
                    }
                }
            })
        }

        binding.btnPlayAll.setOnClickListener { playAll() }

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
        }

        libraryViewModel.message.observe(viewLifecycleOwner) { message ->
            message ?: return@observe
            Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
            libraryViewModel.consumeMessage()
        }
        libraryViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            updateLoadingState(loading)
        }

        refreshCurrentCollection()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun renderSongs(songs: List<Song>, emptyRes: Int) {
        songAdapter.submitList(songs)
        binding.tvCollectionCount.text = getString(R.string.collection_count_value, songs.size)
        binding.tvEmpty.setText(emptyRes)
        binding.layoutSkeleton.visibility = View.GONE
        binding.tvEmpty.visibility = if (songs.isEmpty()) View.VISIBLE else View.GONE
        binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
        binding.btnPlayAll.isEnabled = songs.isNotEmpty()
        if (mode != Mode.PLAYLIST) {
            updateHeaderCover(fallbackUrl = songs.firstOrNull()?.album?.picUrl)
        }
    }

    private fun setHeaderCollapsed(collapsed: Boolean) {
        if (headerCollapsed == collapsed) return
        headerCollapsed = collapsed
        if (collapsed) {
            headerDescriptionVisibility = binding.tvHeaderDescription.visibility
            headerOverlayVisibility = binding.ivHeaderOverlay.visibility
        }
        val visibility = if (collapsed) View.GONE else View.VISIBLE
        binding.tvHeaderEyebrow.visibility = visibility
        binding.headerCoverContainer.visibility = visibility
        binding.tvHeaderDescription.visibility =
            if (collapsed) View.GONE else headerDescriptionVisibility
        binding.ivHeaderOverlay.visibility =
            if (collapsed) View.GONE else headerOverlayVisibility
        binding.btnPlayAll.visibility = visibility
        binding.scrollCollectionStats.visibility = visibility
        binding.headerDivider.visibility = visibility
        (binding.tvHeaderTitle.layoutParams as ConstraintLayout.LayoutParams).apply {
            endToStart = if (collapsed) ConstraintLayout.LayoutParams.UNSET else R.id.headerCoverContainer
            endToEnd = if (collapsed) ConstraintLayout.LayoutParams.PARENT_ID else ConstraintLayout.LayoutParams.UNSET
            binding.tvHeaderTitle.layoutParams = this
        }
        (binding.contentContainer.layoutParams as ConstraintLayout.LayoutParams).apply {
            topToBottom = if (collapsed) R.id.tvHeaderTitle else R.id.headerDivider
            binding.contentContainer.layoutParams = this
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
        when (mode) {
            Mode.LIKED -> libraryViewModel.refreshFavorites(silent = true, forceRefresh = true)
            Mode.HISTORY -> libraryViewModel.refreshHistory(silent = true, forceRefresh = true)
            Mode.PLAYLIST -> {
                libraryViewModel.refreshPlaylists(silent = true, forceRefresh = true)
                libraryViewModel.loadPlaylistSongs(playlistId, forceRefresh = true)
            }
        }
    }

    private fun syncPlaylistHeader(
        songs: List<Song>,
        playlist: UserPlaylist? = libraryViewModel.playlists.value.orEmpty().firstOrNull { it.id == playlistId }
    ) {
        binding.tvHeaderTitle.text = playlist?.name?.takeIf { it.isNotBlank() }
            ?: playlistName.ifBlank { getString(R.string.user_playlist_title) }

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

        updateHeaderCover(
            primaryUrl = playlist?.coverUrl,
            fallbackUrl = songs.firstOrNull()?.album?.picUrl
        )
    }

    private fun updateHeaderCover(primaryUrl: String? = null, fallbackUrl: String? = null) {
        val url = primaryUrl?.trim().takeUnless { it.isNullOrBlank() }
            ?: fallbackUrl?.trim().takeUnless { it.isNullOrBlank() }
            .orEmpty()
        if (url.isBlank()) {
            binding.ivHeaderCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHeaderCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
            binding.ivHeaderOverlay.visibility = View.VISIBLE
        } else {
            binding.ivHeaderCover.imageTintList = null
            binding.ivHeaderOverlay.visibility = View.GONE
            Glide.with(binding.ivHeaderCover)
                .load(url)
                .placeholder(R.drawable.ic_music_note_24)
                .centerCrop()
                .into(binding.ivHeaderCover)
        }
    }

    private fun playAll() {
        val songs = songAdapter.currentList
        if (songs.isEmpty()) return
        musicViewModel.playFromList(songs, songs.first())
    }

    private fun showLikedSongMenu(anchor: View, song: Song) {
        val options = mutableListOf<SongOption>()
        options += SongOption(getString(R.string.action_unlike)) {
            libraryViewModel.setFavorite(song, false)
        }
        options += SongOption(getString(R.string.action_add_to_playlist)) { showAddToPlaylistDialog(song) }
        options += SongOption(getString(R.string.action_download_song)) {
            SongDownloader.download(requireContext(), musicViewModel, song)
        }
        val pinned = libraryViewModel.isPinnedFavorite(song.id)
        options += SongOption(getString(if (pinned) R.string.action_unpin else R.string.action_pin_to_top)) {
            libraryViewModel.togglePinFavorite(song.id)
        }
        SongOptionsBottomSheet.show(parentFragmentManager, song, options)
    }

    private fun showHistorySongMenu(anchor: View, song: Song) {
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        val options = mutableListOf<SongOption>()
        options += SongOption(getString(if (isFavorite) R.string.action_unlike else R.string.action_like)) {
            libraryViewModel.setFavorite(song, !isFavorite)
        }
        val pinned = libraryViewModel.isPinnedHistory(song.id)
        options += SongOption(getString(R.string.action_add_to_playlist)) { showAddToPlaylistDialog(song) }
        options += SongOption(getString(if (pinned) R.string.action_unpin else R.string.action_pin_to_top)) {
            libraryViewModel.togglePinHistory(song.id)
        }
        options += SongOption(getString(R.string.action_delete_history_record)) {
            libraryViewModel.deleteHistoryItem(song.id)
        }
        options += SongOption(getString(R.string.action_download_song)) {
            SongDownloader.download(requireContext(), musicViewModel, song)
        }
        SongOptionsBottomSheet.show(parentFragmentManager, song, options)
    }

    private fun showPlaylistSongMenu(anchor: View, song: Song) {
        if (playlistId.isBlank()) return
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        val options = mutableListOf<SongOption>()
        options += SongOption(getString(if (isFavorite) R.string.action_unlike else R.string.action_like)) {
            libraryViewModel.setFavorite(song, !isFavorite)
        }
        options += SongOption(getString(R.string.action_add_to_playlist)) { showAddToPlaylistDialog(song) }
        options += SongOption(getString(R.string.action_remove_from_playlist)) {
            libraryViewModel.removeSongFromPlaylist(playlistId, song.id)
        }
        options += SongOption(getString(R.string.action_download_song)) {
                SongDownloader.download(requireContext(), musicViewModel, song)
        }
        SongOptionsBottomSheet.show(parentFragmentManager, song, options)
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
