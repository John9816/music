package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.GridLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.MainActivity
import com.music.player.R
import com.music.player.data.model.UserPlaylist
import com.music.player.databinding.FragmentUserPlaylistsBinding
import com.music.player.ui.adapter.UserPlaylistAdapter
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.viewmodel.LibraryViewModel

class UserPlaylistsFragment : Fragment() {

    private var _binding: FragmentUserPlaylistsBinding? = null
    private val binding: FragmentUserPlaylistsBinding
        get() = _binding!!

    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var adapter: UserPlaylistAdapter

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentUserPlaylistsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        adapter = UserPlaylistAdapter(
            onPlaylistClick = { playlist -> openPlaylist(playlist) },
            onPlaylistLongClick = { playlist -> confirmDeletePlaylist(playlist) }
        )

        binding.recyclerView.apply {
            layoutManager = GridLayoutManager(requireContext(), 2)
            adapter = this@UserPlaylistsFragment.adapter
            setHasFixedSize(false)
        }

        binding.swipeRefresh.setColorSchemeColors(requireContext().resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener {
            libraryViewModel.refreshPlaylists(silent = true, forceRefresh = true)
        }
        binding.btnImport.setOnClickListener { showImportDialog() }
        binding.btnEmptyImport.setOnClickListener { showImportDialog() }

        libraryViewModel.playlists.observe(viewLifecycleOwner) { playlists ->
            render(playlists.orEmpty())
        }
        libraryViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            updateLoadingState(loading)
        }
        libraryViewModel.message.observe(viewLifecycleOwner) { message ->
            message ?: return@observe
            Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
            libraryViewModel.consumeMessage()
        }

        libraryViewModel.refreshPlaylists(silent = true, forceRefresh = true)
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    private fun render(playlists: List<UserPlaylist>) {
        adapter.submitList(playlists)
        binding.layoutSkeleton.visibility = View.GONE
        binding.layoutEmpty.visibility = if (playlists.isEmpty()) View.VISIBLE else View.GONE
        binding.recyclerView.visibility = if (playlists.isEmpty()) View.GONE else View.VISIBLE
        binding.tvSubtitle.text = if (playlists.isEmpty()) {
            getString(R.string.user_playlist_empty)
        } else {
            getString(R.string.user_playlist_loaded_count, playlists.size, playlists.first().name)
        }
    }

    private fun updateLoadingState(loading: Boolean) {
        if (_binding == null) return
        val showSkeleton = loading && adapter.currentList.isEmpty()
        binding.layoutSkeleton.visibility = if (showSkeleton) View.VISIBLE else View.GONE
        if (showSkeleton) {
            binding.recyclerView.visibility = View.GONE
            binding.layoutEmpty.visibility = View.GONE
        }
        binding.swipeRefresh.isRefreshing = loading && !showSkeleton
    }

    private fun openPlaylist(playlist: UserPlaylist) {
        (activity as? MainActivity)?.pushDetail(
            SongCollectionFragment.newPlaylist(playlist.id, playlist.name)
        )
    }

    private fun confirmDeletePlaylist(playlist: UserPlaylist) {
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(getString(R.string.user_playlist_delete_title, playlist.name))
            .setMessage(R.string.user_playlist_delete_message)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.user_playlist_delete_confirm) { _, _ ->
                libraryViewModel.deletePlaylist(playlist.id)
            }
            .show()
    }

    private fun showImportDialog() {
        CreatePlaylistBottomSheet().apply {
            onConfirm = { url, _ -> libraryViewModel.createPlaylist(url, null) }
        }.show(parentFragmentManager, "import_playlist")
    }
}
