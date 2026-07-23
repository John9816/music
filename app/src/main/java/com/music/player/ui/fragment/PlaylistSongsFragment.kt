package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.PopupMenu
import android.widget.Toast
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
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.optimizeVerticalScrolling
import com.music.player.ui.viewmodel.MusicViewModel
import com.music.player.ui.viewmodel.LibraryViewModel

class PlaylistSongsFragment : Fragment() {

    companion object {
        private const val ARG_PLAYLIST_ID = "playlist_id"
        private const val ARG_HEADER_TITLE = "header_title"

        fun newInstance(playlistId: String, headerTitle: String? = null): PlaylistSongsFragment = PlaylistSongsFragment().apply {
            arguments = Bundle().apply { putString(ARG_PLAYLIST_ID, playlistId) }
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

        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
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
            binding.tvEmpty.setText(R.string.song_list_empty_playlist)
            binding.tvEmpty.visibility = if (songs.isEmpty()) View.VISIBLE else View.GONE
            binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
            binding.btnPlayAll.isEnabled = songs.isNotEmpty()
        }

        libraryViewModel.message.observe(viewLifecycleOwner) { message ->
            message?.takeIf { it.isNotBlank() }?.let {
                Toast.makeText(requireContext(), it, Toast.LENGTH_SHORT).show()
                libraryViewModel.consumeMessage()
            }
        }

        if (playlistId.isNotBlank()) {
            musicViewModel.loadPlaylistDetailById(playlistId)
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun playAll() {
        val songs = songAdapter.currentList
        if (songs.isEmpty()) return
        musicViewModel.playFromList(songs, songs.first())
    }

    private fun showSongMenu(anchor: View, song: Song) {
        val popup = PopupMenu(requireContext(), anchor)
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        popup.menu.add(if (isFavorite) R.string.action_unfavorite else R.string.action_favorite)
        popup.menu.add(R.string.action_add_to_playlist)
        popup.menu.add(R.string.action_play_next)
        popup.menu.add(R.string.action_add_to_queue)
        popup.menu.add(R.string.action_download_song)

        popup.setOnMenuItemClickListener { item ->
            when (item.title) {
                getString(R.string.action_favorite), getString(R.string.action_unfavorite) -> {
                    libraryViewModel.setFavorite(song, !isFavorite)
                    true
                }
                getString(R.string.action_add_to_playlist) -> {
                    showAddToPlaylistDialog(song)
                    true
                }
                getString(R.string.action_play_next) -> {
                    musicViewModel.enqueueNext(song)
                    Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue_next), Toast.LENGTH_SHORT).show()
                    true
                }
                getString(R.string.action_add_to_queue) -> {
                    musicViewModel.enqueue(song)
                    Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue), Toast.LENGTH_SHORT).show()
                    true
                }
                getString(R.string.action_download_song) -> {
                    SongDownloader.download(requireContext(), musicViewModel, song)
                    true
                }
                else -> false
            }
        }

        popup.show()
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
