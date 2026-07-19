package com.music.player.ui.fragment

import android.content.res.ColorStateList
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.PopupMenu
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentSongCollectionBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.resolveThemeColorStateList
import com.music.player.ui.viewmodel.MusicViewModel

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
    private lateinit var songAdapter: SongAdapter
    private var headerCollapsed = false
    private var headerDescriptionVisibility = View.GONE
    private var headerOverlayVisibility = View.GONE

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
        binding.content.applyStatusBarInsetPadding()

        binding.tvHeaderTitle.visibility = View.VISIBLE
        binding.ivHeaderOverlay.visibility = View.GONE
        binding.btnPlayAll.setOnClickListener { playAll() }

        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onMoreClick = { anchor, song -> showSongMenu(anchor, song) }
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

        musicViewModel.currentPlaylist.observe(viewLifecycleOwner) { playlist ->
            playlist ?: return@observe
            binding.tvHeaderTitle.text = headerTitleOverride ?: playlist.name
            if (playlist.trackCount > 0) {
                binding.tvCollectionCount.text =
                    getString(R.string.collection_count_value, playlist.trackCount)
            }
            updateHeaderCover(playlist.coverImgUrl)

            val description = playlist.description.replace(Regex("\\s+"), " ").trim()
            binding.tvHeaderDescription.text = description
            binding.tvHeaderDescription.visibility = if (description.isBlank()) View.GONE else View.VISIBLE

            val playCountText = formatPlayCount(requireContext(), playlist.playCount)
            binding.tvHeaderPlayCount.text = playCountText
            binding.tvHeaderPlayCount.visibility = if (playlist.playCount > 0) View.VISIBLE else View.GONE
        }

        musicViewModel.playlistSongs.observe(viewLifecycleOwner) { songs ->
            songAdapter.submitList(songs)
            if (musicViewModel.currentPlaylist.value?.trackCount ?: 0 <= 0) {
                binding.tvCollectionCount.text =
                    getString(R.string.collection_count_value, songs.size)
            }
            binding.tvEmpty.setText(R.string.song_list_empty_playlist)
            binding.tvEmpty.visibility = if (songs.isEmpty()) View.VISIBLE else View.GONE
            binding.recyclerView.visibility = if (songs.isEmpty()) View.GONE else View.VISIBLE
            binding.btnPlayAll.isEnabled = songs.isNotEmpty()
        }

        if (playlistId.isNotBlank()) {
            musicViewModel.loadPlaylistDetailById(playlistId)
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun updateHeaderCover(coverUrl: String?) {
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            binding.ivHeaderCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHeaderCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
        } else {
            binding.ivHeaderCover.imageTintList = null
            Glide.with(binding.ivHeaderCover)
                .load(ImageUrl.bestQuality(url))
                .placeholder(R.drawable.ic_music_note_24)
                .centerCrop()
                .into(binding.ivHeaderCover)
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

    private fun formatPlayCount(context: android.content.Context, playCount: Long): String {
        return when {
            playCount >= 100_000_000 -> context.getString(R.string.play_count_yi, playCount / 100_000_000f)
            playCount >= 10_000 -> context.getString(R.string.play_count_wan, playCount / 10_000f)
            else -> context.getString(R.string.play_count_plain, playCount)
        }
    }
}
