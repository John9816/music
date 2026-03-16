package com.music.player.ui.fragment

import android.content.res.ColorStateList
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.bumptech.glide.Glide
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.viewmodel.MusicViewModel

class PlaylistSongsFragment : Fragment() {

    companion object {
        private const val ARG_PLAYLIST_ID = "playlist_id"

        fun newInstance(playlistId: String): PlaylistSongsFragment = PlaylistSongsFragment().apply {
            arguments = Bundle().apply { putString(ARG_PLAYLIST_ID, playlistId) }
        }
    }

    private var _binding: FragmentSongCollectionBinding? = null
    private val binding: FragmentSongCollectionBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var songAdapter: SongAdapter

    private val playlistId: String
        get() = arguments?.getString(ARG_PLAYLIST_ID).orEmpty()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentSongCollectionBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]

        binding.tvHeaderTitle.visibility = View.GONE
        binding.ivHeaderOverlay.visibility = View.GONE
        binding.tvHeaderDescription.visibility = View.GONE
        binding.tvHeaderPlayCount.visibility = View.GONE
        binding.btnPlayAll.setOnClickListener { playAll() }

        songAdapter = SongAdapter(onSongClick = { song -> musicViewModel.playFromList(songAdapter.currentList, song) })
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            setHasFixedSize(false)
        }

        musicViewModel.currentPlaylist.observe(viewLifecycleOwner) { playlist ->
            playlist ?: return@observe
            updateHeaderCover(playlist.coverImgUrl)

            val description = playlist.description.trim()
            binding.tvHeaderDescription.text = description
            binding.tvHeaderDescription.visibility = if (description.isBlank()) View.GONE else View.VISIBLE

            val playCountText = formatPlayCount(requireContext(), playlist.playCount)
            binding.tvHeaderPlayCount.text = playCountText
            binding.tvHeaderPlayCount.visibility = if (playlist.playCount > 0) View.VISIBLE else View.GONE
        }

        musicViewModel.playlistSongs.observe(viewLifecycleOwner) { songs ->
            songAdapter.submitList(songs)
            binding.tvEmpty.setText(R.string.song_list_empty_playlist)
            binding.tvEmpty.visibility = if (songs.isEmpty()) View.VISIBLE else View.GONE
            binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
            binding.btnPlayAll.isEnabled = songs.isNotEmpty()
        }

        if (playlistId.isNotBlank()) {
            musicViewModel.loadPlaylistDetailById(playlistId)
        }
    }

    override fun onStart() {
        super.onStart()
        (activity as? MainActivity)?.setBottomNavVisible(false)
    }

    override fun onStop() {
        super.onStop()
        (activity as? MainActivity)?.setBottomNavVisible(true)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun updateHeaderCover(coverUrl: String?) {
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            binding.ivHeaderCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHeaderCover.imageTintList =
                ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
        } else {
            binding.ivHeaderCover.imageTintList = null
            Glide.with(binding.ivHeaderCover)
                .load(ImageUrl.bestQuality(url))
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

    private fun formatPlayCount(context: android.content.Context, playCount: Long): String {
        return when {
            playCount >= 100_000_000 -> context.getString(R.string.play_count_yi, playCount / 100_000_000f)
            playCount >= 10_000 -> context.getString(R.string.play_count_wan, playCount / 10_000f)
            else -> context.getString(R.string.play_count_plain, playCount)
        }
    }
}
