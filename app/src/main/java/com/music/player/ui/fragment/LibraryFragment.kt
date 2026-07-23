package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.MotionEvent
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
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.Chip
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.model.Song
import com.music.player.data.settings.SearchHistoryManager
import com.music.player.data.settings.MusicSourcePreferences
import com.music.player.databinding.FragmentLibraryBinding
import com.music.player.MainActivity
import com.music.player.ui.adapter.SongAdapter
import com.music.player.ui.adapter.PlaylistGridAdapter
import com.music.player.ui.adapter.SearchArtistAdapter
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.addSlopAwareHeaderCollapseListener
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.optimizeVerticalScrolling
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
    private lateinit var artistAdapter: SearchArtistAdapter
    private lateinit var playlistAdapter: PlaylistGridAdapter
    private lateinit var searchHistoryManager: SearchHistoryManager

    private var isSearchLoading = false
    private var isLibraryLoading = false
    private var isHeroCollapsed = false
    private var heroExpandedHeight = 0
    private var heroCollapsedHeight = 0
    private var searchType = SearchType.SONGS

    private var debounceJob: Job? = null

    companion object {
        private const val DEBOUNCE_MS = 400L
        private const val MIN_QUERY_LENGTH = 2
        private val QUICK_SEARCH_TERMS = listOf(
            "\u5468\u6770\u4f26",
            "\u9648\u5955\u8fc5",
            "Taylor Swift",
            "Adele",
            "YOASOBI",
            "\u6797\u4fca\u6770",
            "\u85a4\u4e95\u98ce",
            "Coldplay"
        )
    }

    private enum class SearchType(val labelRes: Int) {
        SONGS(R.string.search_type_songs),
        ARTISTS(R.string.search_type_artists),
        PLAYLISTS(R.string.search_type_playlists)
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
        setupSourceSelector()
        setupSearchTypeSelector()
        setupObservers()
        setupInteractions()
        setupHistory()
        setupQuickSearch()

        showIdleState()
        renderSongs(emptyList())

        libraryViewModel.prefetch()
    }

    override fun onResume() {
        super.onResume()
        consumePendingSearchFocusRequest()
        refreshHistoryChips()
    }

    override fun onDestroyView() {
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

    override fun onMusicSourceChanged() {
        val binding = _binding ?: return
        syncSourceSelection()
        debounceJob?.cancel()
        renderSongs(emptyList())
        binding.layoutError.visibility = View.GONE
        binding.searchInputLayout.error = null
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            showIdleState()
            return
        }
        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_searching, query)
        collapseHero()
        searchByType(query)
    }

    private fun setupSourceSelector() {
        val sources = MusicSourcePreferences.Source.entries
        binding.chipGroupSources.removeAllViews()
        sources.forEach { source ->
            val chip = Chip(requireContext()).apply {
                id = View.generateViewId()
                text = source.displayName
                isCheckable = true
                isClickable = true
                setEnsureMinTouchTargetSize(true)
                setOnClickListener { selectSearchSource(source) }
            }
            binding.chipGroupSources.addView(chip)
        }
        syncSourceSelection()
    }

    private fun syncSourceSelection() {
        val active = MusicSourcePreferences.activeSource(requireContext())
        val index = MusicSourcePreferences.Source.entries.indexOf(active)
        if (index >= 0 && index < binding.chipGroupSources.childCount) {
            binding.chipGroupSources.check(binding.chipGroupSources.getChildAt(index).id)
        }
    }

    private fun selectSearchSource(source: MusicSourcePreferences.Source) {
        val current = MusicSourcePreferences.activeSource(requireContext())
        if (current == source) return

        MusicSourcePreferences.setActiveSource(requireContext(), source)
        musicViewModel.updateActiveSource(source.storageValue)
        musicViewModel.clearSourceDependentState()
        onMusicSourceChanged()
    }

    private fun setupSearchTypeSelector() {
        binding.chipGroupSearchTypes.removeAllViews()
        SearchType.entries.forEach { type ->
            val chip = Chip(requireContext()).apply {
                id = View.generateViewId()
                text = getString(type.labelRes)
                isCheckable = true
                isClickable = true
                setEnsureMinTouchTargetSize(true)
                setOnClickListener { selectSearchType(type) }
            }
            binding.chipGroupSearchTypes.addView(chip)
        }
        syncSearchTypeSelection()
    }

    private fun syncSearchTypeSelection() {
        val index = SearchType.entries.indexOf(searchType)
        if (index >= 0 && index < binding.chipGroupSearchTypes.childCount) {
            binding.chipGroupSearchTypes.check(binding.chipGroupSearchTypes.getChildAt(index).id)
        }
    }

    private fun selectSearchType(type: SearchType) {
        if (searchType == type) return
        searchType = type
        syncSearchTypeSelection()
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            showIdleState()
            return
        }
        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_searching, query)
        binding.layoutError.visibility = View.GONE
        binding.layoutEmpty.visibility = View.GONE
        collapseHero()
        searchByType(query)
    }

    private fun searchByType(query: String) {
        when (searchType) {
            SearchType.SONGS -> musicViewModel.searchSongs(query)
            SearchType.ARTISTS -> musicViewModel.searchArtists(query)
            SearchType.PLAYLISTS -> musicViewModel.searchPlaylists(query)
        }
    }

    // ── RecyclerView ──────────────────────────────────────────────

    private fun setupRecyclerView() {
        songAdapter = SongAdapter(
            onSongClick = { song -> musicViewModel.playStandaloneSong(song) },
            onSongLongClick = { song -> showSongActions(song) },
            onMoreClick = { _, song -> showSongActions(song) }
        )
        artistAdapter = SearchArtistAdapter { artist ->
            searchType = SearchType.SONGS
            syncSearchTypeSelection()
            binding.etSearch.setText(artist.name)
            binding.etSearch.setSelection(artist.name.length)
            performSearch()
        }
        playlistAdapter = PlaylistGridAdapter { playlist ->
            (activity as? MainActivity)?.pushDetail(
                PlaylistSongsFragment.newInstance(playlist.id, playlist.name)
            )
        }
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = songAdapter
            optimizeVerticalScrolling()
        }
        binding.recyclerView.addOnItemTouchListener(object : RecyclerView.SimpleOnItemTouchListener() {
            override fun onInterceptTouchEvent(rv: RecyclerView, event: MotionEvent): Boolean {
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    hideKeyboardAndClearFocus()
                }
                return false
            }
        })

        binding.recyclerView.addSlopAwareHeaderCollapseListener(
            isCollapsed = { isHeroCollapsed },
            setCollapsed = { collapsed ->
                if (collapsed) collapseHero() else expandHero()
            },
            onScrolledAfterHeader = { rv, _, dy ->
                if (dy <= 0) return@addSlopAwareHeaderCollapseListener
                val lm = rv.layoutManager as? LinearLayoutManager ?: return@addSlopAwareHeaderCollapseListener
                val totalItemCount = lm.itemCount
                val lastVisible = lm.findLastVisibleItemPosition()
                if (searchType == SearchType.SONGS && totalItemCount > 0 && lastVisible >= totalItemCount - 5) {
                    musicViewModel.loadMoreSearchResults()
                }
            }
        )
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
            syncHistoryVisibility()

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
            updateSearchSummary()
        }
        refreshHistoryChips()
    }

    private fun setupQuickSearch() {
        val b = _binding ?: return
        b.chipGroupQuickSearch.removeAllViews()
        QUICK_SEARCH_TERMS.forEach { keyword ->
            val chip = Chip(requireContext()).apply {
                text = keyword
                isCheckable = false
                isClickable = true
                setOnClickListener {
                    b.etSearch.setText(keyword)
                    b.etSearch.setSelection(keyword.length)
                    performSearch()
                }
            }
            b.chipGroupQuickSearch.addView(chip)
        }
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
        updateSearchSummary()

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

    private fun syncHistoryVisibility() {
        val b = _binding ?: return
        b.scrollHistory.visibility = View.GONE
        b.layoutQuickSearch.visibility = View.GONE
        b.scrollSearchSummary.visibility = View.GONE
    }

    // ── Interactions ──────────────────────────────────────────────

    private fun setupInteractions() {
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
        musicViewModel.currentSong.observe(viewLifecycleOwner) { song ->
            songAdapter.setCurrentPlayingId(song?.id)
        }
        musicViewModel.searchResults.observe(viewLifecycleOwner) { songs ->
            if (searchType != SearchType.SONGS) return@observe
            renderSongs(songs)
            val query = binding.etSearch.text?.toString()?.trim().orEmpty()
            if (query.isBlank()) {
                showIdleState()
            } else {
                updateSearchResultSummary(songs.size)
            }
            syncHistoryVisibility()
        }

        musicViewModel.searchArtists.observe(viewLifecycleOwner) { artists ->
            if (searchType != SearchType.ARTISTS) return@observe
            renderArtists(artists)
            updateSearchResultSummary(artists.size)
        }

        musicViewModel.searchPlaylists.observe(viewLifecycleOwner) { playlists ->
            if (searchType != SearchType.PLAYLISTS) return@observe
            renderPlaylists(playlists)
            updateSearchResultSummary(playlists.size)
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

        libraryViewModel.favorites.observe(viewLifecycleOwner) {
            updateSearchSummary()
        }

        libraryViewModel.playlists.observe(viewLifecycleOwner) {
            updateSearchSummary()
        }
    }

    // ── Search Actions ────────────────────────────────────────────

    private fun performSearch() {
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            binding.searchInputLayout.error = getString(R.string.search_input_required)
            binding.etSearch.requestFocus()
            showIdleState()
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
        updateSearchSummary()
        searchByType(query)
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
        searchByType(query)
    }

    private fun refreshSearch() {
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) {
            showIdleState()
            requestSearchFocus()
            return
        }
        searchByType(query)
    }

    // ── Render & State Sync ───────────────────────────────────────

    private fun renderSongs(songs: List<Song>) {
        showResultLayout(SearchType.SONGS)
        songAdapter.submitList(songs) {
            if (_binding != null) {
                songAdapter.setCurrentPlayingId(musicViewModel.currentSong.value?.id)
            }
        }
        syncEmptyState(songs.isEmpty())
        syncHistoryVisibility()
    }

    private fun renderArtists(artists: List<com.music.player.data.model.SearchArtist>) {
        showResultLayout(SearchType.ARTISTS)
        artistAdapter.submitList(artists)
        syncEmptyState(artists.isEmpty())
        syncHistoryVisibility()
    }

    private fun renderPlaylists(playlists: List<com.music.player.data.model.Playlist>) {
        showResultLayout(SearchType.PLAYLISTS)
        playlistAdapter.submitList(playlists)
        syncEmptyState(playlists.isEmpty())
        syncHistoryVisibility()
    }

    private fun showResultLayout(type: SearchType) {
        when (type) {
            SearchType.SONGS, SearchType.ARTISTS -> {
                binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
                binding.recyclerView.adapter = if (type == SearchType.SONGS) songAdapter else artistAdapter
            }
            SearchType.PLAYLISTS -> {
                binding.recyclerView.layoutManager = GridLayoutManager(requireContext(), 2)
                binding.recyclerView.adapter = playlistAdapter
            }
        }
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
        val hasResults = currentResultCount() > 0
        val shouldShowEmpty = !isSearchLoading && !hasError && !hasResults && forceEmpty

        binding.layoutEmpty.visibility = if (shouldShowEmpty) View.VISIBLE else View.GONE
        if (shouldShowEmpty) {
            binding.tvEmptyTitle.text = when (searchType) {
                SearchType.SONGS -> getString(R.string.search_for_songs)
                SearchType.ARTISTS -> getString(R.string.search_for_artists)
                SearchType.PLAYLISTS -> getString(R.string.search_for_playlists)
            }
        }
    }

    private fun syncErrorState(errorMsg: String?) {
        if (errorMsg.isNullOrBlank()) {
            binding.layoutError.visibility = View.GONE
            return
        }
        // Only show inline error if we have no results to display
        if (currentResultCount() == 0) {
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
    }

    private fun updateSearchSummary() {
        val b = _binding ?: return
        val historyCount = searchHistoryManager.getHistory().size
        val favoritesCount = libraryViewModel.favorites.value.orEmpty().size
        val playlistCount = libraryViewModel.playlists.value.orEmpty().size
        b.tvSummaryHistory.text = getString(R.string.search_summary_history_count, historyCount)
        b.tvSummaryFavorites.text = getString(R.string.search_summary_favorites_count, favoritesCount)
        b.tvSummaryPlaylists.text = getString(R.string.search_summary_playlists_count, playlistCount)
    }

    private fun updateSearchResultSummary(count: Int) {
        val query = binding.etSearch.text?.toString()?.trim().orEmpty()
        if (query.isBlank()) return
        binding.tvSectionTitle.text = getString(R.string.search_result_title)
        binding.tvSectionSubtitle.text = if (count == 0) {
            when (searchType) {
                SearchType.SONGS -> getString(R.string.search_not_found_songs)
                SearchType.ARTISTS -> getString(R.string.search_not_found_artists)
                SearchType.PLAYLISTS -> getString(R.string.search_not_found_playlists)
            }
        } else {
            when (searchType) {
                SearchType.SONGS -> getString(R.string.search_found_count_songs, count)
                SearchType.ARTISTS -> getString(R.string.search_found_count_artists, count)
                SearchType.PLAYLISTS -> getString(R.string.search_found_count_playlists, count)
            }
        }
    }

    private fun currentResultCount(): Int = when (searchType) {
        SearchType.SONGS -> musicViewModel.searchResults.value.orEmpty().size
        SearchType.ARTISTS -> musicViewModel.searchArtists.value.orEmpty().size
        SearchType.PLAYLISTS -> musicViewModel.searchPlaylists.value.orEmpty().size
    }

    private fun showIdleState() {
        binding.tvSectionTitle.text = getString(R.string.search_idle_title)
        binding.tvSectionSubtitle.text = getString(R.string.search_idle_subtitle)
        syncHistoryVisibility()
        updateSearchSummary()
    }

    // ── Hero Collapse/Expand ──────────────────────────────────────

    private fun collapseHero() {
        isHeroCollapsed = true
        binding.layoutSearchPanel.animate().cancel()
        binding.layoutSearchPanel.animate()
            .alpha(0f)
            .setDuration(140L)
            .withEndAction {
                binding.layoutSearchPanel.visibility = View.GONE
                binding.heroFrame.minimumHeight = 0
            }
            .start()
    }

    private fun expandHero() {
        isHeroCollapsed = false
        binding.heroFrame.minimumHeight = dp(128)
        binding.layoutSearchPanel.visibility = View.VISIBLE
        binding.layoutSearchPanel.alpha = 0f
        binding.layoutSearchPanel.animate()
            .alpha(1f)
            .setDuration(180L)
            .start()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    // ── Song Actions Dialog ───────────────────────────────────────

    private fun showSongActions(song: Song) {
        val favoriteIds = libraryViewModel.favoriteIds.value.orEmpty()
        val isFavorite = favoriteIds.contains(song.id)

        val options = mutableListOf<SongOption>()
        options += SongOption(getString(if (isFavorite) R.string.action_unfavorite else R.string.action_favorite)) {
            libraryViewModel.setFavorite(song, !isFavorite)
        }
        options += SongOption(getString(R.string.action_play_next)) {
            musicViewModel.enqueueNext(song)
            Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue_next), Toast.LENGTH_SHORT).show()
        }
        options += SongOption(getString(R.string.action_add_to_queue)) {
            musicViewModel.enqueue(song)
            Toast.makeText(requireContext(), getString(R.string.msg_added_to_queue), Toast.LENGTH_SHORT).show()
        }
        options += SongOption(getString(R.string.action_add_to_playlist)) {
            showAddToPlaylistDialog(song)
        }
        options += SongOption(getString(R.string.action_download_song)) {
            SongDownloader.download(requireContext(), musicViewModel, song)
        }
        SongOptionsBottomSheet.show(parentFragmentManager, song, options)
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

        init {
            // Keep list updates snappy; staggered entrance feels laggy on long results.
            addDuration = 120L
            moveDuration = 120L
            removeDuration = 100L
            changeDuration = 100L
        }

        override fun animateAdd(holder: RecyclerView.ViewHolder): Boolean {
            val view = holder.itemView
            view.alpha = 0f
            view.translationY = 12f
            view.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(120)
                .setStartDelay(0L)
                .setInterpolator(FastOutSlowInInterpolator())
                .withEndAction { dispatchAddFinished(holder) }
                .start()
            return true
        }
    }
}
