package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongCollectionHeaderHelper
import com.music.player.ui.util.SongOptionsHelper
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.optimizeVerticalScrolling
import com.music.player.ui.viewmodel.MusicViewModel
import com.music.player.ui.viewmodel.LibraryViewModel

class PlaylistSongsFragment : Fragment() {

    companion object {
        private const val ARG_PLAYLIST_ID = "playlist_id"
        private const val ARG_HEADER_TITLE = "header_title"
        private const val ARG_IS_RANKING = "is_ranking"
        private const val ARG_COVER_URL = "cover_url"
        private const val ARG_DESCRIPTION = "description"
        private const val ARG_TRACK_COUNT = "track_count"
        private const val ARG_PLAY_COUNT = "play_count"

        fun newInstance(
            playlistId: String,
            headerTitle: String? = null,
            isRanking: Boolean = false,
            coverUrl: String? = null,
            description: String? = null,
            trackCount: Int = 0,
            playCount: Long = 0L
        ): PlaylistSongsFragment = PlaylistSongsFragment().apply {
            arguments = Bundle().apply {
                putString(ARG_PLAYLIST_ID, playlistId)
                putBoolean(ARG_IS_RANKING, isRanking)
                coverUrl?.takeIf { it.isNotBlank() }?.let { putString(ARG_COVER_URL, it) }
                description?.takeIf { it.isNotBlank() }?.let { putString(ARG_DESCRIPTION, it) }
                if (trackCount > 0) putInt(ARG_TRACK_COUNT, trackCount)
                if (playCount > 0L) putLong(ARG_PLAY_COUNT, playCount)
            }
            headerTitle?.takeIf { it.isNotBlank() }?.let {
                arguments?.putString(ARG_HEADER_TITLE, it)
            }
        }
    }

    private var _binding: FragmentSongCollectionBinding? = null
    private val binding: FragmentSongCollectionBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var songAdapter: SongAdapter

    private val playlistId: String
        get() = arguments?.getString(ARG_PLAYLIST_ID).orEmpty()

    private val headerTitleOverride: String?
        get() = arguments?.getString(ARG_HEADER_TITLE)?.takeIf { it.isNotBlank() }

    private val isRankingHint: Boolean
        get() = arguments?.getBoolean(ARG_IS_RANKING, false) == true

    private val seedCoverUrl: String?
        get() = arguments?.getString(ARG_COVER_URL)?.takeIf { it.isNotBlank() }

    private val seedDescription: String?
        get() = arguments?.getString(ARG_DESCRIPTION)?.takeIf { it.isNotBlank() }

    private val seedTrackCount: Int
        get() = arguments?.getInt(ARG_TRACK_COUNT, 0) ?: 0

    private val seedPlayCount: Long
        get() = arguments?.getLong(ARG_PLAY_COUNT, 0L) ?: 0L

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentSongCollectionBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        binding.tvHeaderEyebrow.visibility = View.GONE
        binding.tvHeaderTitle.visibility = View.VISIBLE
        binding.ivHeaderOverlay.visibility = View.GONE
        binding.btnPlayAll.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.btnPlayAll.setOnClickListener { playAll() }
        SongCollectionHeaderHelper.setup(
            fragment = this,
            binding = binding,
            initialTitle = headerTitleOverride.orEmpty()
        )
        applySeedHeader()

        songAdapter = SongAdapter(
            // Catalog playlist: play from this row, keep remaining tracks in queue.
            onSongClick = { song ->
                val songs = songAdapter.currentList
                if (songs.isNotEmpty()) {
                    musicViewModel.playFromList(songs, song)
                } else {
                    musicViewModel.playStandaloneSong(song)
                }
            },
            onMoreClick = { anchor, song -> showSongMenu(anchor, song) }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            optimizeVerticalScrolling()
        }

        musicViewModel.currentPlaylist.observe(viewLifecycleOwner) { playlist ->
            playlist ?: return@observe
            SongCollectionHeaderHelper.setTitle(
                binding,
                headerTitleOverride ?: playlist.name
            )
            if (playlist.trackCount > 0) {
                binding.tvCollectionCount.text =
                    getString(R.string.collection_count_value, playlist.trackCount)
            }
            SongCollectionHeaderHelper.loadCovers(binding, playlist.coverImgUrl)

            val description = playlist.description.replace(Regex("\\s+"), " ").trim()
            binding.tvHeaderDescription.text = description
            binding.tvHeaderDescription.visibility = if (description.isBlank()) View.GONE else View.VISIBLE

            val playCountText = formatPlayCount(requireContext(), playlist.playCount)
            binding.tvHeaderPlayCount.text = playCountText
            binding.tvHeaderPlayCount.visibility = if (playlist.playCount > 0) View.VISIBLE else View.GONE
        }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            songAdapter.setCurrentPlayingId(song?.id)
        }

        musicViewModel.playlistSongs.observe(viewLifecycleOwner) { songs ->
            songAdapter.submitList(songs) {
                if (_binding != null) {
                    songAdapter.setCurrentPlayingId(musicViewModel.currentSong.value?.id)
                }
            }
            if (musicViewModel.currentPlaylist.value?.trackCount ?: 0 <= 0) {
                binding.tvCollectionCount.text =
                    getString(R.string.collection_count_value, songs.size)
            }
            val hasError = !musicViewModel.playlistDetailError.value.isNullOrBlank()
            binding.tvEmpty.setText(R.string.song_list_empty_playlist)
            binding.tvEmpty.visibility =
                if (songs.isEmpty() && !hasError) View.VISIBLE else View.GONE
            binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
            binding.btnPlayAll.isEnabled = songs.isNotEmpty()
            if (songs.isNotEmpty()) {
                binding.layoutContentError.visibility = View.GONE
            }
        }

        musicViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            val empty = songAdapter.currentList.isEmpty()
            binding.layoutSkeleton.visibility =
                if (loading == true && empty) View.VISIBLE else View.GONE
            if (loading == true) {
                binding.layoutContentError.visibility = View.GONE
                binding.tvEmpty.visibility = View.GONE
            }
        }

        musicViewModel.playlistDetailError.observe(viewLifecycleOwner) { message ->
            val empty = songAdapter.currentList.isEmpty()
            val loading = musicViewModel.isLoading.value == true
            val show = !message.isNullOrBlank() && empty && !loading
            binding.layoutContentError.visibility = if (show) View.VISIBLE else View.GONE
            if (show) {
                binding.tvContentError.text = message
                binding.tvEmpty.visibility = View.GONE
                binding.recyclerView.visibility = View.GONE
            }
        }

        binding.btnContentRetry.setOnClickListener {
            musicViewModel.clearPlaylistDetailError()
            if (playlistId.isNotBlank()) {
                musicViewModel.loadPlaylistDetailById(playlistId, forceRefresh = true, isRanking = isRankingHint)
            }
        }

        if (playlistId.isNotBlank()) {
            musicViewModel.loadPlaylistDetailById(playlistId, isRanking = isRankingHint)
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    /**
     * Paint the header from the list card immediately — cover, count, play count, description
     * come from the tile the user just tapped, so the detail screen looks "there" while
     * playlist/detail is still in flight. Real data overwrites these in the observer above.
     */
    private fun applySeedHeader() {
        SongCollectionHeaderHelper.loadCovers(binding, seedCoverUrl)

        val trackCount = seedTrackCount
        if (trackCount > 0) {
            binding.tvCollectionCount.text =
                getString(R.string.collection_count_value, trackCount)
        }

        val description = seedDescription?.replace(Regex("\\s+"), " ")?.trim().orEmpty()
        binding.tvHeaderDescription.text = description
        binding.tvHeaderDescription.visibility = if (description.isBlank()) View.GONE else View.VISIBLE

        val playCount = seedPlayCount
        if (playCount > 0L) {
            binding.tvHeaderPlayCount.text = formatPlayCount(requireContext(), playCount)
            binding.tvHeaderPlayCount.visibility = View.VISIBLE
        } else {
            binding.tvHeaderPlayCount.visibility = View.GONE
        }
    }

    private fun playAll() {
        val songs = songAdapter.currentList
        if (songs.isEmpty()) return
        musicViewModel.playFromList(songs, songs.first())
    }

    private fun showSongMenu(@Suppress("UNUSED_PARAMETER") anchor: View, song: Song) {
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        SongOptionsHelper.showStandard(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = ::showAddToPlaylistDialog,
            isFavorite = isFavorite,
            onToggleFavorite = { libraryViewModel.setFavorite(song, !isFavorite) }
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
            "${playlist.name} - $count"
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

    private fun formatPlayCount(context: android.content.Context, playCount: Long): String {
        return when {
            playCount >= 100_000_000 -> context.getString(R.string.play_count_yi, playCount / 100_000_000f)
            playCount >= 10_000 -> context.getString(R.string.play_count_wan, playCount / 10_000f)
            else -> context.getString(R.string.play_count_plain, playCount)
        }
    }
}
