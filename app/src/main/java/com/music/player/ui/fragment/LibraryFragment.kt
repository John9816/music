package com.music.player.ui.fragment

import android.animation.ValueAnimator
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.core.content.getSystemService
import androidx.core.view.doOnLayout
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.Fragment
import androidx.interpolator.view.animation.FastOutSlowInInterpolator
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DefaultItemAnimator
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.Chip
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.data.settings.SearchHistoryManager
import com.music.player.databinding.FragmentLibraryBinding
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class LibraryFragment : Fragment(), RootTabInteraction {

    private var _binding: FragmentLibraryBinding? = null
    private val binding: FragmentLibraryBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private lateinit var songAdapter: SongAdapter
    private lateinit var searchHistoryManager: SearchHistoryManager

    private var isSearchLoading = false
    private var isLibraryLoading = false
    private var isUserRefreshing = false
    private var isHeroCollapsed = false
    private var heroExpandedHeight = 0
    private var heroCollapsedHeight = 0
    private var heroAnimator: ValueAnimator? = null

    private var debounceJob: Job? = null

    companion object {
        private const val DEBOUNCE_MS = 400L
        private const val MIN_QUERY_LENGTH = 2
    }

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
        searchHistoryManager = SearchHistoryManager(requireContext())

        heroExpandedHeight = resources.getDimensionPixelSize(R.dimen.library_hero_height)

        binding.layoutHeroContent.applyStatusBarInsetPadding()
        binding.heroFrame.doOnLayout { heroFrame ->
            if (!isHeroCollapsed) {
                heroExpandedHeight = heroFrame.height.coerceAtLeast(heroExpandedHeight)
            }
        }
        binding.layoutSearchPanel.doOnLayout { searchPanel ->
            heroCollapsedHeight = searchPanel.height
        }
        setupRecyclerView()
        setupInput()
        setupObservers()
        setupInteractions()
        setupHistory()

        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_hint)
        renderSongs(emptyList())

        libraryViewModel.prefetch()
    }

    override fun onResume() {
        super.onResume()
        consumePendingSearchFocusRequest()
        refreshHistoryChips()
    }

    override fun onDestroyView() {
        heroAnimator?.cancel()
        debounceJob?.cancel()
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

    // ── RecyclerView ──────────────────────────────────────────────

    private fun setupRecyclerView() {
        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onSongLongClick = { song -> showSongActions(song) }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            setHasFixedSize(true)
            itemAnimator = SearchItemAnimator()
        }
        binding.recyclerView.setOnTouchListener { _, _ ->
            hideKeyboardAndClearFocus()
            false
        }

        // Infinite scroll for pagination
        binding.recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                if (dy <= 0) return
                val lm = rv.layoutManager as? LinearLayoutManager ?: return
                val totalItemCount = lm.itemCount
                val lastVisible = lm.findLastVisibleItemPosition()
                if (totalItemCount > 0 && lastVisible >= totalItemCount - 5) {
                    musicViewModel.loadMoreSearchResults()
                }
            }
        })
    }

    // ── Input ─────────────────────────────────────────────────────

    private fun setupInput() {
        binding.etSearch.setOnClickListener { binding.etSearch.requestFocus() }
        binding.root.setOnClickListener { hideKeyboardAndClearFocus() }
        binding.cardSongList.setOnClickListener { hideKeyboardAndClearFocus() }

        binding.etSearch.doAfterTextChanged { editable ->
            binding.searchInputLayout.error = null
            syncSearchActionState()

            val query = editable?.toString()?.trim().orEmpty()

            // Show/hide history based on empty input
            syncHistoryVisibility(query)

            // Expand hero if query cleared
            if (query.isEmpty()) {
                expandHero()
            }

            // Debounced real-time search
            debounceJob?.cancel()
            if (query.length >= MIN_QUERY_LENGTH) {
                debounceJob = viewLifecycleOwner.lifecycleScope.launch {
                    delay(DEBOUNCE_MS)
                    performSearchQuiet(query)
                }
            }
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

    // ── History ───────────────────────────────────────────────────

    private fun setupHistory() {
        binding.btnClearHistory.setOnClickListener {
            searchHistoryManager.clearAll()
            refreshHistoryChips()
        }
        refreshHistoryChips()
    }

    private fun refreshHistoryChips() {
        val b = _binding ?: return
        val history = searchHistoryManager.getHistory()
        b.chipGroupHistory.removeAllViews()

        if (history.isEmpty()) {
            b.scrollHistory.visibility = View.GONE
            return
        }

        val query = b.etSearch.text?.toString()?.trim().orEmpty()
        b.scrollHistory.visibility = if (query.isEmpty() && songAdapter.currentList.isEmpty()) View.VISIBLE else View.GONE

        history.forEach { keyword ->
            val chip = Chip(requireContext()).apply {
                text = keyword
                isCheckable = false
                isClickable = true
                setOnClickListener {
                    b.etSearch.setText(keyword)
                    b.etSearch.setSelection(keyword.length)
                    performSearch()
                }
                setOnLongClickListener {
                    searchHistoryManager.removeQuery(keyword)
                    refreshHistoryChips()
                    true
                }
            }
            b.chipGroupHistory.addView(chip)
        }
    }

    private fun syncHistoryVisibility(query: String) {
        val b = _binding ?: return
        val history = searchHistoryManager.getHistory()
        val shouldShow = query.isEmpty() && history.isNotEmpty() && songAdapter.currentList.isEmpty()
        b.scrollHistory.visibility = if (shouldShow) View.VISIBLE else View.GONE
    }

    // ── Interactions ──────────────────────────────────────────────

    private fun setupInteractions() {
        binding.swipeRefresh.setColorSchemeColors(requireContext().resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener { refreshSearch() }
        binding.btnRetry.setOnClickListener { performSearch() }
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

    // ── Observers ─────────────────────────────────────────────────

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
            syncHistoryVisibility(binding.etSearch.text?.toString()?.trim().orEmpty())
        }

        musicViewModel.isSearchLoading.observe(viewLifecycleOwner) { loading ->
            isSearchLoading = loading
            syncLoadingState()
            syncEmptyState()
        }

        musicViewModel.searchError.observe(viewLifecycleOwner) { errorMsg ->
            syncErrorState(errorMsg)
        }

        musicViewModel.isLoadingMore.observe(viewLifecycleOwner) { loading ->
            binding.progressLoadMore.visibility = if (loading) View.VISIBLE else View.GONE
        }

        libraryViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            isLibraryLoading = loading
            // Only affect progressBar for library-level loading, not search UI
            binding.progressBar.visibility = if (loading && !isSearchLoading) View.VISIBLE else View.GONE
        }
    }

    // ── Search Actions ────────────────────────────────────────────

    private fun performSearch() {
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            binding.searchInputLayout.error = getString(R.string.search_input_required)
            binding.etSearch.requestFocus()
            stopRefreshIndicator()
            return
        }
        debounceJob?.cancel()
        binding.searchInputLayout.error = null
        binding.layoutEmpty.visibility = View.GONE
        binding.layoutError.visibility = View.GONE
        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_searching, query)
        hideKeyboardAndClearFocus()
        collapseHero()
        searchHistoryManager.addQuery(query)
        musicViewModel.searchSongs(query)
    }

    /** Debounced auto-search — does not hide keyboard or save history */
    private fun performSearchQuiet(query: String) {
        if (query.isBlank()) return
        binding.searchInputLayout.error = null
        binding.layoutEmpty.visibility = View.GONE
        binding.layoutError.visibility = View.GONE
        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_searching, query)
        collapseHero()
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

    // ── Render & State Sync ───────────────────────────────────────

    private fun renderSongs(songs: List<Song>) {
        songAdapter.submitList(songs)
        syncEmptyState(songs.isEmpty())
    }

    private fun syncLoadingState() {
        // Skeleton for search loading, ProgressBar only for library loading
        binding.layoutSkeleton.visibility = if (isSearchLoading) View.VISIBLE else View.GONE
        binding.recyclerView.visibility = if (isSearchLoading) View.INVISIBLE else View.VISIBLE
        syncSearchActionState()

        // Hide error when loading starts
        if (isSearchLoading) {
            binding.layoutError.visibility = View.GONE
            binding.layoutEmpty.visibility = View.GONE
        }
    }

    private fun syncEmptyState(forceEmpty: Boolean = musicViewModel.searchResults.value.orEmpty().isEmpty()) {
        val hasError = musicViewModel.searchError.value != null
        val hasResults = musicViewModel.searchResults.value.orEmpty().isNotEmpty()
        val shouldShowEmpty = !isSearchLoading &&
            !hasError &&
            !hasResults &&
            forceEmpty &&
            binding.etSearch.text?.toString()?.trim().orEmpty().isNotEmpty()

        binding.layoutEmpty.visibility = if (shouldShowEmpty) View.VISIBLE else View.GONE
    }

    private fun syncErrorState(errorMsg: String?) {
        if (errorMsg.isNullOrBlank()) {
            binding.layoutError.visibility = View.GONE
            return
        }
        // Only show inline error if we have no results to display
        if (musicViewModel.searchResults.value.orEmpty().isEmpty()) {
            binding.layoutError.visibility = View.VISIBLE
            binding.tvErrorMessage.text = errorMsg
            binding.layoutEmpty.visibility = View.GONE
            binding.layoutSkeleton.visibility = View.GONE
        } else {
            // Have existing results — just show a toast, don't replace the list
            binding.layoutError.visibility = View.GONE
            Toast.makeText(requireContext(), errorMsg, Toast.LENGTH_SHORT).show()
        }
    }

    private fun syncSearchActionState() {
        val loading = isSearchLoading
        val hasQuery = binding.etSearch.text?.toString()?.trim().isNullOrEmpty() == false
        binding.btnSearch.isEnabled = hasQuery && !loading
        binding.swipeRefresh.isEnabled = hasQuery && !loading
    }

    private fun stopRefreshIndicator() {
        isUserRefreshing = false
        binding.swipeRefresh.isRefreshing = false
    }

    // ── Hero Collapse/Expand ──────────────────────────────────────

    private fun collapseHero() {
        if (isHeroCollapsed) return
        isHeroCollapsed = true
        val fromHeight = binding.heroFrame.height.takeIf { it > 0 } ?: heroExpandedHeight
        val toHeight = heroCollapsedHeight.takeIf { it > 0 } ?: fromHeight
        binding.layoutHeroContent.animate().cancel()
        binding.layoutHeroContent.alpha = 0f
        binding.layoutHeroContent.visibility = View.GONE
        animateHeroHeight(fromHeight, toHeight)
    }

    private fun expandHero() {
        if (!isHeroCollapsed) return
        isHeroCollapsed = false
        val fromHeight = binding.heroFrame.height.takeIf { it > 0 } ?: heroCollapsedHeight
        val toHeight = heroExpandedHeight.takeIf { it > 0 } ?: fromHeight
        binding.layoutHeroContent.visibility = View.VISIBLE
        binding.layoutHeroContent.alpha = 0f
        animateHeroHeight(fromHeight, toHeight)
        binding.layoutHeroContent.animate()
            .alpha(1f)
            .setDuration(250)
            .setInterpolator(FastOutSlowInInterpolator())
            .start()
    }

    private fun animateHeroHeight(from: Int, to: Int) {
        heroAnimator?.cancel()
        heroAnimator = ValueAnimator.ofInt(from, to).apply {
            duration = 300L
            interpolator = FastOutSlowInInterpolator()
            addUpdateListener { animator ->
                val b = _binding ?: return@addUpdateListener
                val value = animator.animatedValue as Int
                val lp = b.heroFrame.layoutParams
                lp.height = value
                b.heroFrame.layoutParams = lp
            }
            start()
        }
    }

    // ── Song Actions Dialog ───────────────────────────────────────

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

    // ── Utilities ─────────────────────────────────────────────────

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

    // ── Custom ItemAnimator for search results ────────────────────

    private class SearchItemAnimator : DefaultItemAnimator() {

        override fun animateAdd(holder: RecyclerView.ViewHolder): Boolean {
            val view = holder.itemView
            view.alpha = 0f
            view.translationY = 40f
            view.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(250)
                .setStartDelay((holder.bindingAdapterPosition * 30L).coerceAtMost(150))
                .setInterpolator(FastOutSlowInInterpolator())
                .withEndAction { dispatchAddFinished(holder) }
                .start()
            return true
        }
    }
}
