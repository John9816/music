package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.BottomSheetQueueBinding
import com.music.player.databinding.ItemQueueSongBinding
import com.music.player.playback.PlaybackCoordinator.PlaylistViewMode
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongOptionsHelper
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel

/**
 * NetEase-like queue sheet:
 * - Tab「当前播放」: now playing + up-next (full session list mental model)
 * - Tab「历史」: recently played from navigation history
 * - Overflow menu via [SongOptionsHelper] (queue remove, download, playlist, favorite)
 * - Clear only wipes up-next, not the current song
 */
class QueueBottomSheetFragment : BottomSheetDialogFragment() {

    private var _binding: BottomSheetQueueBinding? = null
    private val binding: BottomSheetQueueBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private var currentSong: Song? = null
    private var queueSongs: List<Song> = emptyList()
    private var recentSongs: List<Song> = emptyList()
    private var viewMode: PlaylistViewMode = PlaylistViewMode.QUEUE
    private var visibleCount = PAGE_SIZE

    private val queueAdapter = QueueAdapter(
        onPlay = { song ->
            when (viewMode) {
                PlaylistViewMode.QUEUE -> {
                    val playing = currentSong
                    if (playing != null && playing.id == song.id) {
                        Toast.makeText(
                            requireContext(),
                            getString(R.string.queue_playing_badge),
                            Toast.LENGTH_SHORT
                        ).show()
                    } else {
                        musicViewModel.playFromQueue(song.id)
                        dismiss()
                    }
                }
                PlaylistViewMode.RECENT -> {
                    musicViewModel.playFromRecent(song.id)
                    dismiss()
                }
            }
        },
        onMore = { song -> showQueueSongMenu(song) }
    )

    private companion object {
        const val PAGE_SIZE = 50
        const val LOAD_MORE_THRESHOLD = 8
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = BottomSheetQueueBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        dialog?.let { dlg ->
            val sheet = dlg.findViewById<android.widget.FrameLayout>(
                com.google.android.material.R.id.design_bottom_sheet
            )
            if (sheet != null) {
                val behavior = BottomSheetBehavior.from(sheet)
                sheet.layoutParams = sheet.layoutParams.apply {
                    height = ViewGroup.LayoutParams.MATCH_PARENT
                }
                behavior.skipCollapsed = true
                behavior.peekHeight = resources.displayMetrics.heightPixels
                behavior.state = BottomSheetBehavior.STATE_EXPANDED
            }
        }

        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = queueAdapter
        binding.recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy <= 0) return
                val sourceSize = when (viewMode) {
                    PlaylistViewMode.QUEUE -> queueSongs.size + (if (currentSong != null) 1 else 0)
                    PlaylistViewMode.RECENT -> recentSongs.size
                }
                if (visibleCount >= sourceSize) return
                val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
                if (layoutManager.findLastVisibleItemPosition() >=
                    (recyclerView.adapter?.itemCount ?: 0) - LOAD_MORE_THRESHOLD
                ) {
                    visibleCount = (visibleCount + PAGE_SIZE).coerceAtMost(sourceSize)
                    render()
                }
            }
        })

        binding.btnClose.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnClear.bindPressFeedback(PressFeedback.Style.BUTTON)
        binding.btnClose.setOnClickListener { dismiss() }
        binding.btnClear.setOnClickListener {
            when (viewMode) {
                PlaylistViewMode.QUEUE -> {
                    musicViewModel.clearQueue()
                    Toast.makeText(
                        requireContext(),
                        getString(R.string.msg_queue_cleared),
                        Toast.LENGTH_SHORT
                    ).show()
                }
                PlaylistViewMode.RECENT -> {
                    // History clear is per-item only; keep button for queue tab.
                }
            }
        }

        binding.toggleMode.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked) return@addOnButtonCheckedListener
            val mode = when (checkedId) {
                R.id.btnHistoryMode -> PlaylistViewMode.RECENT
                else -> PlaylistViewMode.QUEUE
            }
            if (viewMode == mode) return@addOnButtonCheckedListener
            viewMode = mode
            visibleCount = PAGE_SIZE
            musicViewModel.setPlaylistViewMode(mode)
            render()
        }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            currentSong = song
            render()
        }
        musicViewModel.queue.observe(viewLifecycleOwner) { queue ->
            queueSongs = queue.orEmpty()
            render()
        }
        musicViewModel.recentlyPlayed.observe(viewLifecycleOwner) { recent ->
            recentSongs = recent.orEmpty()
            render()
        }
        musicViewModel.playlistViewMode.observe(viewLifecycleOwner) { mode ->
            val resolved = mode ?: PlaylistViewMode.QUEUE
            if (viewMode != resolved) {
                viewMode = resolved
                binding.toggleMode.check(
                    if (resolved == PlaylistViewMode.RECENT) R.id.btnHistoryMode
                    else R.id.btnQueueMode
                )
            }
            render()
        }
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    private fun showQueueSongMenu(song: Song) {
        val isFavorite = libraryViewModel.favoriteIds.value.orEmpty().contains(song.id)
        val inQueueTab = viewMode == PlaylistViewMode.QUEUE
        val removeLabel = if (inQueueTab) {
            getString(R.string.action_remove_from_queue)
        } else {
            getString(R.string.action_remove_from_history)
        }
        SongOptionsHelper.show(
            context = requireContext(),
            fragmentManager = parentFragmentManager,
            song = song,
            musicViewModel = musicViewModel,
            onAddToPlaylist = ::showAddToPlaylistDialog,
            config = SongOptionsHelper.Config(
                // Queue tab already holds these tracks; play-next reorders to front.
                includePlayNext = true,
                includeAddToQueue = !inQueueTab,
                isFavorite = isFavorite,
                onToggleFavorite = { libraryViewModel.setFavorite(song, !isFavorite) },
                favoriteLabels = R.string.action_unlike to R.string.action_like,
                extraTrailing = listOf(
                    SongOption(removeLabel) {
                        when (viewMode) {
                            PlaylistViewMode.QUEUE -> {
                                val wasCurrent = currentSong?.id == song.id
                                musicViewModel.removeFromQueue(song.id)
                                Toast.makeText(
                                    requireContext(),
                                    if (wasCurrent) {
                                        getString(R.string.queue_removed_current)
                                    } else {
                                        getString(R.string.msg_removed_from_queue)
                                    },
                                    Toast.LENGTH_SHORT
                                ).show()
                            }
                            PlaylistViewMode.RECENT -> {
                                musicViewModel.removeFromRecentlyPlayed(song.id)
                                Toast.makeText(
                                    requireContext(),
                                    getString(R.string.msg_removed_from_queue),
                                    Toast.LENGTH_SHORT
                                ).show()
                            }
                        }
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

    private fun render() {
        val playing = currentSong
        when (viewMode) {
            PlaylistViewMode.QUEUE -> {
                val full = buildList {
                    if (playing != null) add(playing)
                    addAll(queueSongs)
                }
                if (visibleCount < PAGE_SIZE && full.isNotEmpty()) {
                    visibleCount = PAGE_SIZE.coerceAtMost(full.size)
                }
                val display = full.take(visibleCount.coerceAtMost(full.size))
                binding.tvTitle.text = getString(R.string.queue_tab_playing)
                binding.tvSubtitle.text = getString(
                    R.string.queue_subtitle_up_next,
                    full.size,
                    queueSongs.size
                )
                binding.btnClear.isEnabled = queueSongs.isNotEmpty()
                binding.btnClear.visibility =
                    if (queueSongs.isNotEmpty()) View.VISIBLE else View.INVISIBLE
                binding.btnClear.text = getString(R.string.queue_clear)
                queueAdapter.setState(songId = playing?.id, allowRemoveCurrent = true)
                queueAdapter.submitList(display)
                binding.tvEmptyState.visibility = if (full.isEmpty()) View.VISIBLE else View.GONE
                binding.tvEmptyState.text = getString(R.string.queue_empty)
            }
            PlaylistViewMode.RECENT -> {
                if (visibleCount < PAGE_SIZE && recentSongs.isNotEmpty()) {
                    visibleCount = PAGE_SIZE.coerceAtMost(recentSongs.size)
                }
                val display = recentSongs.take(visibleCount.coerceAtMost(recentSongs.size))
                binding.tvTitle.text = getString(R.string.queue_tab_history)
                binding.tvSubtitle.text = getString(
                    R.string.queue_subtitle_history,
                    recentSongs.size
                )
                binding.btnClear.visibility = View.INVISIBLE
                binding.btnClear.isEnabled = false
                queueAdapter.setState(songId = playing?.id, allowRemoveCurrent = true)
                queueAdapter.submitList(display)
                binding.tvEmptyState.visibility = if (display.isEmpty()) View.VISIBLE else View.GONE
                binding.tvEmptyState.text = getString(R.string.queue_history_empty)
            }
        }
    }

    private class QueueAdapter(
        private val onPlay: (Song) -> Unit,
        private val onMore: (Song) -> Unit
    ) : ListAdapter<Song, QueueAdapter.ViewHolder>(DiffCallback()) {

        private var currentSongId: String? = null
        private var allowRemoveCurrent: Boolean = true

        fun setState(songId: String?, allowRemoveCurrent: Boolean) {
            currentSongId = songId
            this.allowRemoveCurrent = allowRemoveCurrent
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val binding = ItemQueueSongBinding.inflate(
                LayoutInflater.from(parent.context),
                parent,
                false
            )
            return ViewHolder(binding)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            holder.bind(getItem(position), currentSongId, allowRemoveCurrent, onPlay, onMore)
        }

        class ViewHolder(
            private val binding: ItemQueueSongBinding
        ) : RecyclerView.ViewHolder(binding.root) {
            private var boundSong: Song? = null
            private var playAction: ((Song) -> Unit)? = null
            private var moreAction: ((Song) -> Unit)? = null

            init {
                binding.root.bindPressFeedback(PressFeedback.Style.ROW)
                binding.btnRemove.bindPressFeedback(PressFeedback.Style.ICON)
                binding.root.setOnClickListener { boundSong?.let { playAction?.invoke(it) } }
                binding.btnRemove.setOnClickListener {
                    boundSong?.let { moreAction?.invoke(it) }
                }
            }

            fun bind(
                song: Song,
                currentSongId: String?,
                allowRemoveCurrent: Boolean,
                onPlay: (Song) -> Unit,
                onMore: (Song) -> Unit
            ) {
                boundSong = song
                playAction = onPlay
                moreAction = onMore
                val isPlayingItem = currentSongId != null && currentSongId == song.id
                binding.ivPlaying.visibility = if (isPlayingItem) View.VISIBLE else View.GONE
                binding.playingBar.visibility = if (isPlayingItem) View.VISIBLE else View.GONE
                binding.root.isSelected = isPlayingItem
                binding.tvSong.text = song.name
                binding.tvArtist.text = song.artists.joinToString(", ") { it.name }

                val context = binding.root.context
                val playingColor = context.resolveThemeColor(R.attr.brandPrimary)
                val songColor = context.resolveThemeColor(R.attr.textPrimary)
                val artistColor = context.resolveThemeColor(R.attr.textSecondary)
                binding.tvSong.setTextColor(if (isPlayingItem) playingColor else songColor)
                binding.tvArtist.setTextColor(if (isPlayingItem) playingColor else artistColor)
                binding.tvDot.setTextColor(if (isPlayingItem) playingColor else artistColor)
                binding.btnRemove.visibility =
                    if (allowRemoveCurrent || !isPlayingItem) View.VISIBLE else View.GONE
                val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
                if (coverUrl == null) {
                    binding.ivCover.setImageResource(R.drawable.ic_music_note_24)
                } else {
                    Glide.with(binding.ivCover)
                        .load(ImageUrl.thumbnail(coverUrl, 160))
                        .placeholder(R.drawable.ic_music_note_24)
                        .centerCrop()
                        .dontAnimate()
                        .into(binding.ivCover)
                }
            }
        }

        private class DiffCallback : DiffUtil.ItemCallback<Song>() {
            override fun areItemsTheSame(oldItem: Song, newItem: Song): Boolean =
                oldItem.id == newItem.id

            override fun areContentsTheSame(oldItem: Song, newItem: Song): Boolean =
                oldItem == newItem
        }
    }
}
