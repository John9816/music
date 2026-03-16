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
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.BottomSheetQueueBinding
import com.music.player.databinding.ItemQueueSongBinding
import com.music.player.ui.viewmodel.MusicViewModel

class QueueBottomSheetFragment : BottomSheetDialogFragment() {

    private var _binding: BottomSheetQueueBinding? = null
    private val binding: BottomSheetQueueBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private var currentSong: Song? = null
    private var queueSongs: List<Song> = emptyList()
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
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]

        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = queueAdapter

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
            addAll(queueSongs)
        }

        queueAdapter.setCurrentSongId(playing?.id)
        queueAdapter.submitList(display)

        binding.tvEmptyState.visibility = if (display.isEmpty()) View.VISIBLE else View.GONE
        binding.btnClear.isEnabled = queueSongs.isNotEmpty()

        val title = getString(R.string.queue_title)
        binding.tvTitle.text = if (display.isEmpty()) title else "$title (${display.size})"
    }

    private class QueueAdapter(
        private val onPlay: (Song) -> Unit,
        private val onRemove: (Song) -> Unit
    ) : ListAdapter<Song, QueueAdapter.ViewHolder>(DiffCallback()) {

        private var currentSongId: String? = null

        fun setCurrentSongId(songId: String?) {
            currentSongId = songId
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val binding = ItemQueueSongBinding.inflate(LayoutInflater.from(parent.context), parent, false)
            return ViewHolder(binding)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            holder.bind(getItem(position), currentSongId, onPlay, onRemove)
        }

        class ViewHolder(
            private val binding: ItemQueueSongBinding
        ) : RecyclerView.ViewHolder(binding.root) {
            fun bind(song: Song, currentSongId: String?, onPlay: (Song) -> Unit, onRemove: (Song) -> Unit) {
                val isPlaying = currentSongId != null && currentSongId == song.id
                binding.ivPlaying.visibility = if (isPlaying) View.VISIBLE else View.GONE
                binding.root.setBackgroundColor(
                    binding.root.context.getColor(if (isPlaying) R.color.surface_alt else android.R.color.transparent)
                )
                binding.tvSong.text = song.name
                binding.tvArtist.text = song.artists.joinToString(", ") { it.name }

                val context = binding.root.context
                val playingColor = context.getColor(android.R.color.holo_red_light)
                val songColor = context.getColor(R.color.text_primary)
                val artistColor = context.getColor(R.color.text_secondary)
                binding.tvSong.setTextColor(if (isPlaying) playingColor else songColor)
                binding.tvArtist.setTextColor(if (isPlaying) playingColor else artistColor)
                binding.tvDot.setTextColor(if (isPlaying) playingColor else artistColor)
                binding.btnRemove.visibility = if (isPlaying) View.INVISIBLE else View.VISIBLE
                binding.root.setOnClickListener { onPlay(song) }
                binding.btnRemove.setOnClickListener {
                    if (!isPlaying) onRemove(song)
                }
            }
        }

        private class DiffCallback : DiffUtil.ItemCallback<Song>() {
            override fun areItemsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem.id == newItem.id
            override fun areContentsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem == newItem
        }
    }
}
