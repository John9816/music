package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.core.content.getSystemService
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentLibraryBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel

class LibraryFragment : Fragment(), RootTabInteraction {

    private var _binding: FragmentLibraryBinding? = null
    private val binding: FragmentLibraryBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var songAdapter: SongAdapter

    private var isMusicLoading = false
    private var isLibraryLoading = false
    private var isUserRefreshing = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentLibraryBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        setupRecyclerView()
        setupInput()
        setupObservers()
        setupInteractions()

        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_hint)
        binding.tvEmptyState.text = getString(R.string.song_list_empty_search)
        renderSongs(emptyList())

        libraryViewModel.prefetch()
    }

    override fun onResume() {
        super.onResume()
        consumePendingSearchFocusRequest()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    override fun onTabReselected() {
        val binding = _binding ?: return
        if (binding.recyclerView.canScrollVertically(-1)) {
            binding.recyclerView.smoothScrollToPosition(0)
            return
        }
        if (binding.etSearch.text?.isNullOrBlank() != false) {
            requestSearchFocus()
            return
        }
        refreshSearch()
    }

    private fun setupRecyclerView() {
        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onSongLongClick = { song -> showSongActions(song) }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            setHasFixedSize(true)
        }
        binding.recyclerView.setOnTouchListener { _, _ ->
            hideKeyboardAndClearFocus()
            false
        }
    }

    private fun setupInput() {
        binding.etSearch.setOnClickListener { binding.etSearch.requestFocus() }
        binding.root.setOnClickListener { hideKeyboardAndClearFocus() }
        binding.cardSongList.setOnClickListener { hideKeyboardAndClearFocus() }
        binding.tvEmptyState.setOnClickListener { hideKeyboardAndClearFocus() }
        binding.etSearch.doAfterTextChanged {
            binding.searchInputLayout.error = null
            syncSearchActionState()
        }

        binding.etSearch.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                performSearch()
                true
            } else {
                false
            }
        }

        binding.btnSearch.setOnClickListener { performSearch() }
    }

    private fun setupInteractions() {
        binding.swipeRefresh.setColorSchemeColors(requireContext().resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener { refreshSearch() }
        syncSearchActionState()
    }

    fun requestSearchFocus() {
        val context = context ?: return
        binding.etSearch.post {
            if (_binding == null) return@post
            binding.searchInputLayout.error = null
            binding.etSearch.requestFocus()
            binding.etSearch.setSelection(binding.etSearch.text?.length ?: 0)
            val imm = context.getSystemService<InputMethodManager>()
            imm?.showSoftInput(binding.etSearch, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun setupObservers() {
        musicViewModel.searchResults.observe(viewLifecycleOwner) { songs ->
            renderSongs(songs)
            binding.tvSectionTitle.text = getString(R.string.search_result_title)
            binding.tvSectionSubtitle.text = if (songs.isEmpty()) {
                getString(R.string.search_not_found)
            } else {
                getString(R.string.search_found_count, songs.size)
            }
            stopRefreshIndicator()
        }

        musicViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            isMusicLoading = loading
            syncLoadingState()
            syncEmptyState()
        }

        libraryViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            isLibraryLoading = loading
            syncLoadingState()
        }
    }

    private fun performSearch() {
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            binding.searchInputLayout.error = getString(R.string.search_input_required)
            binding.etSearch.requestFocus()
            stopRefreshIndicator()
            return
        }
        binding.searchInputLayout.error = null

        binding.tvEmptyState.visibility = View.GONE
        syncEmptyState(forceEmpty = false)
        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_searching, query)
        hideKeyboardAndClearFocus()
        musicViewModel.searchSongs(query)
    }

    private fun refreshSearch() {
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            stopRefreshIndicator()
            requestSearchFocus()
            return
        }
        isUserRefreshing = true
        binding.swipeRefresh.isRefreshing = true
        binding.swipeRefresh.postDelayed({
            if (_binding != null && isUserRefreshing) {
                stopRefreshIndicator()
            }
        }, 3000L)
        musicViewModel.searchSongs(query)
    }

    private fun renderSongs(songs: List<Song>) {
        songAdapter.submitList(songs)
        syncEmptyState(songs.isEmpty())
    }

    private fun syncLoadingState() {
        val anyLoading = isMusicLoading || isLibraryLoading
        binding.progressBar.visibility = if (anyLoading) View.VISIBLE else View.GONE
        syncSearchActionState()
    }

    private fun syncEmptyState(forceEmpty: Boolean = songAdapter.currentList.isEmpty()) {
        val anyLoading = isMusicLoading || isLibraryLoading
        binding.tvEmptyState.visibility = if (anyLoading || !forceEmpty) View.GONE else View.VISIBLE
    }

    private fun syncSearchActionState() {
        val anyLoading = isMusicLoading || isLibraryLoading
        val hasQuery = binding.etSearch.text?.toString()?.trim().isNullOrEmpty().not()
        binding.btnSearch.isEnabled = hasQuery && !anyLoading
        binding.swipeRefresh.isEnabled = hasQuery && !anyLoading
    }

    private fun stopRefreshIndicator() {
        isUserRefreshing = false
        binding.swipeRefresh.isRefreshing = false
    }

    private fun showSongActions(song: Song) {
        val favoriteIds = libraryViewModel.favoriteIds.value.orEmpty()
        val isFavorite = favoriteIds.contains(song.id)

        val items = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        items += getString(if (isFavorite) R.string.action_unfavorite else R.string.action_favorite)
        actions += { libraryViewModel.setFavorite(song, !isFavorite) }

        items += getString(R.string.action_add_to_playlist)
        actions += { showAddToPlaylistDialog(song) }

        items += getString(R.string.action_play_next)
        actions += {
            musicViewModel.enqueueNext(song)
            Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue_next), Toast.LENGTH_SHORT).show()
        }

        items += getString(R.string.action_add_to_queue)
        actions += {
            musicViewModel.enqueue(song)
            Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue), Toast.LENGTH_SHORT).show()
        }

        MaterialAlertDialogBuilder(requireContext())
            .setTitle(song.name)
            .setItems(items.toTypedArray()) { _, which -> actions[which].invoke() }
            .show()
    }

    private fun showAddToPlaylistDialog(song: Song) {
        val playlists = libraryViewModel.playlists.value.orEmpty()
        if (playlists.isEmpty()) {
            Toast.makeText(requireContext(), getString(R.string.user_playlist_create_first), Toast.LENGTH_SHORT).show()
            return
        }

        val names = playlists.map { it.name }.toTypedArray()
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.user_playlist_pick_title)
            .setItems(names) { _, which ->
                libraryViewModel.addSongToPlaylist(playlists[which].id, song)
            }
            .show()
    }

    private fun hideKeyboardAndClearFocus() {
        val imm = context?.getSystemService<InputMethodManager>() ?: return
        binding.etSearch.clearFocus()
        imm.hideSoftInputFromWindow(binding.etSearch.windowToken, 0)
    }

    private fun consumePendingSearchFocusRequest() {
        val activity = activity as? com.music.player.MainActivity ?: return
        if (!activity.intent.getBooleanExtra(com.music.player.MainActivity.EXTRA_FOCUS_LIBRARY_SEARCH, false)) {
            return
        }
        activity.intent.removeExtra(com.music.player.MainActivity.EXTRA_FOCUS_LIBRARY_SEARCH)
        requestSearchFocus()
    }
}
