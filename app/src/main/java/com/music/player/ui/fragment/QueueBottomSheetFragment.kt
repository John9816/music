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
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.BottomSheetQueueBinding
import com.music.player.databinding.ItemQueueSongBinding
import com.music.player.ui.util.ImageUrl
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.viewmodel.MusicViewModel

class QueueBottomSheetFragment : BottomSheetDialogFragment() {

    private var _binding: BottomSheetQueueBinding? = null
    private val binding: BottomSheetQueueBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private var currentSong: Song? = null
    private var queueSongs: List<Song> = emptyList()
    private var visibleQueueCount = PAGE_SIZE
    private val queueAdapter = QueueAdapter(
        onPlay = { song ->
            val playing = currentSong
            if (playing != null && playing.id == song.id) {
                Toast.makeText(requireContext(), getString(R.string.queue_playing_badge), Toast.LENGTH_SHORT).show()
            } else {
                musicViewModel.playFromQueue(song.id)
                dismiss()
            }
        },
        onRemove = { song ->
            musicViewModel.removeFromQueue(song.id)
            Toast.makeText(requireContext(), getString(R.string.msg_removed_from_queue), Toast.LENGTH_SHORT).show()
        }
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
            val sheet = dlg.findViewById<android.widget.FrameLayout>(com.google.android.material.R.id.design_bottom_sheet)
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

        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = queueAdapter
        binding.recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy <= 0 || visibleQueueCount >= queueSongs.size) return
                val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
                if (layoutManager.findLastVisibleItemPosition() >=
                    recyclerView.adapter.orEmptyItemCount() - LOAD_MORE_THRESHOLD
                ) {
                    visibleQueueCount = (visibleQueueCount + PAGE_SIZE).coerceAtMost(queueSongs.size)
                    render()
                }
            }
        })

        binding.btnClose.setOnClickListener { dismiss() }
        binding.btnClear.setOnClickListener {
            musicViewModel.clearQueue()
            Toast.makeText(requireContext(), getString(R.string.msg_queue_cleared), Toast.LENGTH_SHORT).show()
        }

        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            currentSong = song
            render()
        }

        musicViewModel.queue.observe(viewLifecycleOwner) { queue ->
            queueSongs = queue
            visibleQueueCount = visibleQueueCount.coerceAtMost(queue.size).coerceAtLeast(PAGE_SIZE)
            render()
        }
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    private fun render() {
        val playing = currentSong
        val display = buildList {
            if (playing != null) add(playing)
            addAll(queueSongs.take(visibleQueueCount))
        }

        queueAdapter.setState(
            songId = playing?.id,
            showRemove = true
        )
        queueAdapter.submitList(display)

        binding.tvEmptyState.visibility = if (display.isEmpty()) View.VISIBLE else View.GONE
        binding.tvEmptyState.text = getString(R.string.queue_empty)
        binding.btnClear.isEnabled = queueSongs.isNotEmpty()
        binding.btnClear.visibility = if (queueSongs.isNotEmpty()) View.VISIBLE else View.GONE

        val itemCount = if (display.isEmpty()) 0 else display.size
        binding.tvTitle.text = getString(R.string.queue_title)
        binding.tvSubtitle.text = getString(R.string.queue_subtitle_up_next, itemCount)
    }

    private fun RecyclerView.Adapter<*>?.orEmptyItemCount(): Int = this?.itemCount ?: 0

    private class QueueAdapter(
        private val onPlay: (Song) -> Unit,
        private val onRemove: (Song) -> Unit
    ) : ListAdapter<Song, QueueAdapter.ViewHolder>(DiffCallback()) {

        private var currentSongId: String? = null
        private var showRemove: Boolean = false

        fun setState(songId: String?, showRemove: Boolean) {
            currentSongId = songId
            this.showRemove = showRemove
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val binding = ItemQueueSongBinding.inflate(LayoutInflater.from(parent.context), parent, false)
            return ViewHolder(binding)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            holder.bind(getItem(position), currentSongId, showRemove, onPlay, onRemove)
        }

        class ViewHolder(
            private val binding: ItemQueueSongBinding
        ) : RecyclerView.ViewHolder(binding.root) {
            fun bind(
                song: Song,
                currentSongId: String?,
                showRemove: Boolean,
                onPlay: (Song) -> Unit,
                onRemove: (Song) -> Unit
            ) {
                val isPlaying = currentSongId != null && currentSongId == song.id
                binding.ivPlaying.visibility = if (isPlaying) View.VISIBLE else View.GONE
                binding.root.setBackgroundResource(
                    if (isPlaying) R.drawable.bg_queue_item_active else R.drawable.bg_queue_item
                )
                binding.tvSong.text = song.name
                binding.tvArtist.text = song.artists.joinToString(", ") { it.name }

                val context = binding.root.context
                val playingColor = context.resolveThemeColor(R.attr.brandPrimary)
                val songColor = context.resolveThemeColor(R.attr.textPrimary)
                val artistColor = context.resolveThemeColor(R.attr.textSecondary)
                binding.tvSong.setTextColor(if (isPlaying) playingColor else songColor)
                binding.tvArtist.setTextColor(if (isPlaying) playingColor else artistColor)
                binding.tvDot.setTextColor(if (isPlaying) playingColor else artistColor)
                binding.btnRemove.visibility = View.VISIBLE
                val coverUrl = song.album.picUrl.takeIf { it.isNotBlank() }
                if (coverUrl == null) {
                    binding.ivCover.setImageResource(R.drawable.ic_music_note_24)
                } else {
                    Glide.with(binding.ivCover)
                        .load(ImageUrl.bestQuality(coverUrl))
                        .placeholder(R.drawable.ic_music_note_24)
                        .centerCrop()
                        .dontAnimate()
                        .into(binding.ivCover)
                }
                binding.root.setOnClickListener { onPlay(song) }
                binding.btnRemove.setOnClickListener {
                    if (!isPlaying && showRemove) onRemove(song)
                }
            }
        }

        private class DiffCallback : DiffUtil.ItemCallback<Song>() {
            override fun areItemsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem.id == newItem.id
            override fun areContentsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem == newItem
        }
    }
}
