package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.BottomSheetSongOptionsBinding
import com.music.player.databinding.ItemSongOptionBinding
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

data class SongOption(val label: String, val action: () -> Unit)

class SongOptionsBottomSheet : BottomSheetDialogFragment() {

    var songName: String = ""
    var options: List<SongOption> = emptyList()

    private var _binding: BottomSheetSongOptionsBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = BottomSheetSongOptionsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.tvSongTitle.text = songName
        binding.rvOptions.layoutManager = LinearLayoutManager(requireContext())
        binding.rvOptions.adapter = OptionsAdapter(options)
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    private inner class OptionsAdapter(
        private val items: List<SongOption>
    ) : RecyclerView.Adapter<OptionsAdapter.VH>() {

        inner class VH(val binding: ItemSongOptionBinding) : RecyclerView.ViewHolder(binding.root)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            VH(ItemSongOptionBinding.inflate(LayoutInflater.from(parent.context), parent, false))

        override fun getItemCount() = items.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            holder.binding.tvOptionLabel.text = items[position].label
            holder.binding.root.setOnClickListener {
                items[position].action()
                dismiss()
            }
        }
    }

    companion object {
        fun show(
            fragmentManager: androidx.fragment.app.FragmentManager,
            song: Song,
            options: List<SongOption>
        ) {
            SongOptionsBottomSheet().apply {
                songName = song.name
                this.options = options
            }.show(fragmentManager, "song_options")
        }
    }
}
