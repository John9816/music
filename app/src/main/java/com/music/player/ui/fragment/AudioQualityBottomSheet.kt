package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.music.player.R
import com.music.player.data.settings.AudioQualityPreferences
import com.music.player.databinding.BottomSheetAudioQualityBinding
import com.music.player.databinding.ItemAudioQualityBinding
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

class AudioQualityBottomSheet : BottomSheetDialogFragment() {

    var onQualitySelected: ((AudioQualityPreferences.Level) -> Unit)? = null

    private var _binding: BottomSheetAudioQualityBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = BottomSheetAudioQualityBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val levels = AudioQualityPreferences.Level.entries.toList()
        val current = AudioQualityPreferences.getPreferredLevel(requireContext())

        binding.rvQualities.layoutManager = LinearLayoutManager(requireContext())
        binding.rvQualities.adapter = QualityAdapter(levels, current) { selected ->
            AudioQualityPreferences.setPreferredLevel(requireContext(), selected)
            onQualitySelected?.invoke(selected)
            dismiss()
        }
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    private inner class QualityAdapter(
        private val levels: List<AudioQualityPreferences.Level>,
        private val current: AudioQualityPreferences.Level,
        private val onClick: (AudioQualityPreferences.Level) -> Unit
    ) : RecyclerView.Adapter<QualityAdapter.VH>() {

        inner class VH(val binding: ItemAudioQualityBinding) : RecyclerView.ViewHolder(binding.root)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            return VH(ItemAudioQualityBinding.inflate(LayoutInflater.from(parent.context), parent, false))
        }

        override fun getItemCount() = levels.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            val level = levels[position]
            holder.binding.tvQualityName.text = level.displayName
            holder.binding.ivCheck.visibility = if (level == current) View.VISIBLE else View.INVISIBLE
            holder.binding.root.setOnClickListener { onClick(level) }
        }
    }
}
