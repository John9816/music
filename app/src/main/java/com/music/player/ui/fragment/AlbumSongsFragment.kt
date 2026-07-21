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
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.Album
import com.music.player.data.model.NewestAlbum
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.optimizeVerticalScrolling
import com.music.player.ui.util.resolveThemeColorStateList
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
        binding.content.applyStatusBarInsetPadding()

        binding.tvHeaderEyebrow.text = getString(R.string.album_header_eyebrow)
        binding.tvHeaderTitle.text = albumName.ifBlank { getString(R.string.album_header_title_fallback) }
        binding.tvHeaderDescription.text = artistNames.ifBlank { getString(R.string.album_header_description_fallback) }
        binding.tvHeaderDescription.visibility = View.VISIBLE
        binding.tvCollectionMode.text = getString(R.string.album_collection_mode)
        binding.tvCollectionCount.text = getString(R.string.collection_count_default)
        binding.ivHeaderOverlay.visibility = View.GONE
        binding.tvHeaderPlayCount.visibility = View.GONE
        binding.btnPlayAll.setOnClickListener { playAll() }

        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onMoreClick = { anchor, song -> showSongMenu(anchor, song) }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            optimizeVerticalScrolling()
        }

        musicViewModel.currentAlbum.observe(viewLifecycleOwner) { album ->
            if (album == null || album.album.id != albumId) return@observe
            binding.tvHeaderTitle.text = album.album.name.ifBlank { albumName }
            binding.tvHeaderDescription.text = album.artistNames.ifBlank { artistNames }
            binding.tvHeaderDescription.visibility = View.VISIBLE
            updateHeaderCover(album.album.picUrl.ifBlank { coverUrl })
        }

        musicViewModel.currentAlbumSongs.observe(viewLifecycleOwner) { songs ->
            songAdapter.submitList(songs)
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

        musicViewModel.error.observe(viewLifecycleOwner) { message ->
            if (message.isNullOrBlank()) return@observe
            Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
        }

        updateHeaderCover(coverUrl)
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

    private fun updateHeaderCover(url: String?) {
        val normalized = url?.trim().orEmpty()
        if (normalized.isBlank()) {
            binding.ivHeaderCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHeaderCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
            return
        }
        binding.ivHeaderCover.imageTintList = null
        Glide.with(binding.ivHeaderCover)
            .load(ImageUrl.bestQuality(normalized))
            .placeholder(R.drawable.ic_music_note_24)
            .centerCrop()
            .into(binding.ivHeaderCover)
    }

    private fun playAll() {
        val songs = songAdapter.currentList
        if (songs.isEmpty()) return
        musicViewModel.playFromList(songs, songs.first())
    }

    private fun showSongMenu(anchor: View, song: Song) {
        val popup = PopupMenu(requireContext(), anchor)
        popup.menu.add(R.string.action_play_next)
        popup.menu.add(R.string.action_add_to_queue)
        popup.menu.add(R.string.action_download_song)

        popup.setOnMenuItemClickListener { item ->
            when (item.title) {
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
}
