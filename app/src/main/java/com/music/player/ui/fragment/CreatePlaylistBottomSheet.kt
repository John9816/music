package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.music.player.R
import com.music.player.databinding.BottomSheetCreatePlaylistBinding

class CreatePlaylistBottomSheet : BottomSheetDialogFragment() {

    var onConfirm: ((name: String, desc: String) -> Unit)? = null

    private var _binding: BottomSheetCreatePlaylistBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = BottomSheetCreatePlaylistBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.btnCancel.setOnClickListener { dismiss() }
        binding.btnConfirm.setOnClickListener {
            val name = binding.etPlaylistName.text?.toString()?.trim().orEmpty()
            val desc = binding.etPlaylistDesc.text?.toString()?.trim().orEmpty()
            if (name.isBlank()) {
                Toast.makeText(requireContext(), getString(R.string.user_playlist_name_required), Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            onConfirm?.invoke(name, desc)
            dismiss()
        }
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }
}
