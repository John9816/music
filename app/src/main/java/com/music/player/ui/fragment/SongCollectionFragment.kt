package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.appcompat.widget.PopupMenu
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.bumptech.glide.Glide
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel

class SongCollectionFragment : Fragment() {

    enum class Mode { LIKED, HISTORY }

    companion object {
        private const val ARG_MODE = "mode"

        fun newLiked(): SongCollectionFragment = SongCollectionFragment().apply {
            arguments = Bundle().apply { putString(ARG_MODE, Mode.LIKED.name) }
        }

        fun newHistory(): SongCollectionFragment = SongCollectionFragment().apply {
            arguments = Bundle().apply { putString(ARG_MODE, Mode.HISTORY.name) }
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

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentSongCollectionBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        val titleRes = if (mode == Mode.LIKED) R.string.profile_liked_title else R.string.profile_history_title
        binding.tvHeaderTitle.setText(titleRes)
        binding.tvHeaderDescription.visibility = View.GONE
        binding.tvHeaderPlayCount.visibility = View.GONE
        binding.ivHeaderOverlay.visibility = View.VISIBLE
        binding.ivHeaderOverlay.setImageResource(if (mode == Mode.LIKED) R.drawable.ic_favorite_24 else R.drawable.ic_play_24)

        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playFromList(songAdapter.currentList, song) },
            onMoreClick = { anchor, song ->
                when (mode) {
                    Mode.LIKED -> showLikedSongMenu(anchor, song)
                    Mode.HISTORY -> showHistorySongMenu(anchor, song)
                }
            }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            setHasFixedSize(false)
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

        libraryViewModel.message.observe(viewLifecycleOwner) { message ->
            message ?: return@observe
            Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
            libraryViewModel.consumeMessage()
        }

        when (mode) {
            Mode.LIKED -> libraryViewModel.refreshFavorites()
            Mode.HISTORY -> libraryViewModel.refreshHistory()
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

    private fun renderSongs(songs: List<com.music.player.data.model.Song>, emptyRes: Int) {
        songAdapter.submitList(songs)
        binding.tvEmpty.setText(emptyRes)
        binding.tvEmpty.visibility = if (songs.isEmpty()) View.VISIBLE else View.GONE
        binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
        binding.btnPlayAll.isEnabled = songs.isNotEmpty()
        updateHeaderCover(songs.firstOrNull()?.album?.picUrl)
    }

    private fun updateHeaderCover(coverUrl: String?) {
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            binding.ivHeaderCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHeaderCover.imageTintList =
                android.content.res.ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
        } else {
            binding.ivHeaderCover.imageTintList = null
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

    private fun showLikedSongMenu(anchor: View, song: com.music.player.data.model.Song) {
        val popup = PopupMenu(requireContext(), anchor).apply {
            menuInflater.inflate(R.menu.song_more_menu, menu)
        }

        popup.menu.findItem(R.id.action_unfavorite)?.title = getString(R.string.action_unlike)

        val pinned = libraryViewModel.isPinnedFavorite(song.id)
        popup.menu.findItem(R.id.action_pin)?.title =
            getString(if (pinned) R.string.action_unpin else R.string.action_pin_to_top)

        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_unfavorite -> {
                    libraryViewModel.setFavorite(song, false)
                    true
                }
                R.id.action_pin -> {
                    libraryViewModel.togglePinFavorite(song.id)
                    true
                }
                else -> false
            }
        }

        popup.show()
    }

    private fun showHistorySongMenu(anchor: View, song: com.music.player.data.model.Song) {
        val popup = PopupMenu(requireContext(), anchor).apply {
            menuInflater.inflate(R.menu.song_history_more_menu, menu)
        }

        val pinned = libraryViewModel.isPinnedHistory(song.id)
        popup.menu.findItem(R.id.action_pin)?.title =
            getString(if (pinned) R.string.action_unpin else R.string.action_pin_to_top)

        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_pin -> {
                    libraryViewModel.togglePinHistory(song.id)
                    true
                }
                R.id.action_delete_history -> {
                    libraryViewModel.deleteHistoryItem(song.id)
                    true
                }
                else -> false
            }
        }

        popup.show()
    }
}
