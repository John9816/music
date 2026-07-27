package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.music.player.R
import com.music.player.data.model.Album
import com.music.player.data.model.NewestAlbum
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongCollectionHeaderHelper
import com.music.player.ui.util.SongOptionsHelper
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.optimizeVerticalScrolling
import com.music.player.ui.viewmodel.MusicViewModel

class AlbumSongsFragment : Fragment() {

    companion object {
        private const val ARG_ALBUM_ID = "album_id"
        private const val ARG_ALBUM_NAME = "album_name"
        private const val ARG_ARTIST_NAMES = "artist_names"
        private const val ARG_COVER_URL = "cover_url"

        fun newInstance(
            albumId: String,
            albumName: String,
            artistNames: String,
            coverUrl: String
        ): AlbumSongsFragment = AlbumSongsFragment().apply {
            arguments = Bundle().apply {
                putString(ARG_ALBUM_ID, albumId)
                putString(ARG_ALBUM_NAME, albumName)
                putString(ARG_ARTIST_NAMES, artistNames)
                putString(ARG_COVER_URL, coverUrl)
            }
        }
    }

    private var _binding: FragmentSongCollectionBinding? = null
    private val binding: FragmentSongCollectionBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var songAdapter: SongAdapter

    private val albumId: String
        get() = arguments?.getString(ARG_ALBUM_ID).orEmpty()

    private val albumName: String
        get() = arguments?.getString(ARG_ALBUM_NAME).orEmpty()

    private val artistNames: String
        get() = arguments?.getString(ARG_ARTIST_NAMES).orEmpty()

    private val coverUrl: String
        get() = arguments?.getString(ARG_COVER_URL).orEmpty()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentSongCollectionBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]

        binding.tvHeaderEyebrow.text = getString(R.string.album_header_eyebrow)
        val title = albumName.ifBlank { getString(R.string.album_header_title_fallback) }
        binding.tvHeaderDescription.text = artistNames.ifBlank { getString(R.string.album_header_description_fallback) }
        binding.tvHeaderDescription.visibility = View.VISIBLE
        binding.tvCollectionMode.text = getString(R.string.album_collection_mode)
        binding.tvCollectionCount.text = getString(R.string.collection_count_default)
        binding.ivHeaderOverlay.visibility = View.GONE
        binding.tvHeaderPlayCount.visibility = View.GONE
        binding.btnPlayAll.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.btnPlayAll.setOnClickListener { playAll() }
        SongCollectionHeaderHelper.setup(this, binding, title)
        SongCollectionHeaderHelper.loadCovers(binding, coverUrl)

        songAdapter = SongAdapter(
            // Album track list context — same as "play all" but start at the tapped song.
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

        musicViewModel.currentAlbum.observe(viewLifecycleOwner) { album ->
            if (album == null || album.album.id != albumId) return@observe
            SongCollectionHeaderHelper.setTitle(
                binding,
                album.album.name.ifBlank { albumName }
            )
            binding.tvHeaderDescription.text = album.artistNames.ifBlank { artistNames }
            binding.tvHeaderDescription.visibility = View.VISIBLE
            SongCollectionHeaderHelper.loadCovers(
                binding,
                album.album.picUrl.ifBlank { coverUrl }
            )
        }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            songAdapter.setCurrentPlayingId(song?.id)
        }

        musicViewModel.currentAlbumSongs.observe(viewLifecycleOwner) { songs ->
            songAdapter.submitList(songs) {
                if (_binding != null) {
                    songAdapter.setCurrentPlayingId(musicViewModel.currentSong.value?.id)
                }
            }
            binding.tvCollectionCount.text = getString(R.string.collection_count_value, songs.size)
            binding.layoutSkeleton.visibility = View.GONE
            binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
            binding.tvEmpty.visibility = if (songs.isEmpty()) View.VISIBLE else View.GONE
            binding.tvEmpty.text = getString(R.string.album_empty)
            binding.btnPlayAll.isEnabled = songs.isNotEmpty()
        }

        musicViewModel.currentAlbumLoading.observe(viewLifecycleOwner) { loading ->
            val showSkeleton = loading && songAdapter.currentList.isEmpty()
            binding.layoutSkeleton.visibility = if (showSkeleton) View.VISIBLE else View.GONE
            if (showSkeleton) {
                binding.recyclerView.visibility = View.GONE
                binding.tvEmpty.visibility = View.GONE
            }
        }

        musicViewModel.albumDetailError.observe(viewLifecycleOwner) { message ->
            val empty = songAdapter.currentList.isEmpty()
            val loading = musicViewModel.currentAlbumLoading.value == true
            val show = !message.isNullOrBlank() && empty && !loading
            binding.layoutContentError.visibility = if (show) View.VISIBLE else View.GONE
            if (show) {
                binding.tvContentError.text = message
                binding.tvEmpty.visibility = View.GONE
                binding.recyclerView.visibility = View.GONE
            }
        }

        binding.btnContentRetry.setOnClickListener {
            musicViewModel.clearAlbumDetailError()
            refreshAlbum(forceRefresh = true)
        }

        refreshAlbum(forceRefresh = false)
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    private fun refreshAlbum(forceRefresh: Boolean) {
        val album = NewestAlbum(
            album = Album(
                id = albumId,
                name = albumName,
                picUrl = coverUrl
            ),
            artistNames = artistNames
        )
        musicViewModel.loadNewestAlbumDetail(album, forceRefresh = forceRefresh)
    }

    private fun playAll() {
        val songs = songAdapter.currentList
        if (songs.isEmpty()) return
        musicViewModel.playFromList(songs, songs.first())
    }

    private fun showSongMenu(@Suppress("UNUSED_PARAMETER") anchor: View, song: Song) {
        SongOptionsHelper.show(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = { /* album list: no playlist picker wired */ },
            config = SongOptionsHelper.Config(includeAddToPlaylist = false)
        )
    }
}
