package com.music.player.ui.fragment

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.tabs.TabLayout
import com.music.player.R
import com.music.player.data.model.Playlist
import com.music.player.data.model.PlaylistCategory
import com.music.player.data.settings.MusicSourcePreferences
import com.music.player.databinding.FragmentPlaylistsBinding
import com.music.player.ui.adapter.PlaylistCategoryChipAdapter
import com.music.player.ui.adapter.RadioPlaylistAdapter
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.viewmodel.MusicViewModel

class PlaylistsFragment : Fragment(), RootTabInteraction {

    private enum class RadioTab { RANKINGS, PLAYLISTS }

    private var _binding: FragmentPlaylistsBinding? = null
    private val binding: FragmentPlaylistsBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var adapter: RadioPlaylistAdapter
    private lateinit var categoryAdapter: PlaylistCategoryChipAdapter
    private var selectedTab = RadioTab.RANKINGS
    private var rankingsRequested = false
    private var playlistsRequested = false
    private var rankingsLoaded = false
    private var playlistsLoaded = false
    private var allItems: List<Playlist> = emptyList()
    private var selectedCategory = ""
    private var selectedGroupId: Int? = null
    private var groupTabIds: List<Int?> = emptyList()
    private var rebuildingGroupTabs = false
    private var loadingMore = false
    private var hasMorePlaylists = true
    private var previousPlaylistCount = 0
    private var radioHeaderCollapsed = false

    private companion object {
        const val STATE_TAB = "radio_selected_tab"
        const val STATE_CATEGORY = "radio_playlist_category"
        const val STATE_GROUP_ID = "radio_playlist_group_id"
        const val PLAYLIST_PAGE_SIZE = 42
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentPlaylistsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        selectedTab = savedInstanceState?.getString(STATE_TAB)
            ?.let { runCatching { RadioTab.valueOf(it) }.getOrNull() }
            ?: RadioTab.RANKINGS
        selectedCategory = savedInstanceState?.getString(STATE_CATEGORY).orEmpty()
        selectedGroupId = savedInstanceState?.getInt(STATE_GROUP_ID, Int.MIN_VALUE)
            ?.takeUnless { it == Int.MIN_VALUE }

        binding.layoutHeroContent.applyStatusBarInsetPadding()
        setupList()
        setupCategories()
        setupTabs()
        setupSearch()
        setupInteractions()
        setupObservers()
        selectTab(selectedTab, forceRefresh = false)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString(STATE_TAB, selectedTab.name)
        outState.putString(STATE_CATEGORY, selectedCategory)
        outState.putInt(STATE_GROUP_ID, selectedGroupId ?: Int.MIN_VALUE)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    override fun onTabReselected() {
        val binding = _binding ?: return
        val layoutManager = binding.recyclerView.layoutManager as? LinearLayoutManager
        if ((layoutManager?.findFirstVisibleItemPosition() ?: 0) > 0) {
            binding.recyclerView.smoothScrollToPosition(0)
        } else {
            refreshCurrentTab()
        }
    }

    override fun onMusicSourceChanged() {
        if (_binding == null) return
        rankingsRequested = false
        playlistsRequested = false
        rankingsLoaded = false
        playlistsLoaded = false
        allItems = emptyList()
        selectedCategory = ""
        selectedGroupId = null
        loadingMore = false
        hasMorePlaylists = true
        previousPlaylistCount = 0
        categoryAdapter.selectedApiName = ""
        rebuildGroupTabs(emptyList())
        adapter.submitList(emptyList())
        musicViewModel.loadPlaylistCategories(forceRefresh = true)
        selectTab(selectedTab, forceRefresh = true)
    }

    private fun setupList() {
        adapter = RadioPlaylistAdapter(::openPlaylist)
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@PlaylistsFragment.adapter
            setHasFixedSize(true)
            itemAnimator = null
            addOnScrollListener(object : androidx.recyclerview.widget.RecyclerView.OnScrollListener() {
                override fun onScrolled(
                    recyclerView: androidx.recyclerview.widget.RecyclerView,
                    dx: Int,
                    dy: Int
                ) {
                    if (dy > 0 && !radioHeaderCollapsed) {
                        setRadioHeaderCollapsed(true)
                    } else if (dy < 0 && !recyclerView.canScrollVertically(-1) && radioHeaderCollapsed) {
                        setRadioHeaderCollapsed(false)
                    }
                    if (dy <= 0 || selectedTab != RadioTab.PLAYLISTS || loadingMore || !hasMorePlaylists) {
                        return
                    }
                    val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
                    if (layoutManager.findLastVisibleItemPosition() >= this@PlaylistsFragment.adapter.itemCount - 5) {
                        previousPlaylistCount = allItems.size
                        loadingMore = true
                        musicViewModel.loadTopPlaylists(
                            category = selectedCategory,
                            limit = PLAYLIST_PAGE_SIZE,
                            offset = allItems.size,
                            append = true
                        )
                    }
                }
            })
        }
    }

    private fun setupCategories() {
        categoryAdapter = PlaylistCategoryChipAdapter(
            showGroupName = false,
            onClick = ::selectCategory
        )
        binding.rvCategories.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
            adapter = categoryAdapter
            itemAnimator = null
        }
        categoryAdapter.selectedApiName = selectedCategory

        binding.playlistGroupTabs.addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab) {
                if (!rebuildingGroupTabs) {
                    selectCategoryGroup(groupTabIds.getOrNull(tab.position))
                }
            }

            override fun onTabUnselected(tab: TabLayout.Tab) = Unit
            override fun onTabReselected(tab: TabLayout.Tab) = Unit
        })
    }

    private fun setRadioHeaderCollapsed(collapsed: Boolean) {
        if (radioHeaderCollapsed == collapsed) return
        radioHeaderCollapsed = collapsed
        val visibility = if (collapsed) View.GONE else View.VISIBLE
        binding.tabLayout.visibility = visibility
        binding.radioSearchBar.visibility = visibility
        binding.tvPlaylistCategoryLabel.visibility =
            if (!collapsed && selectedTab == RadioTab.PLAYLISTS) View.VISIBLE else View.GONE
        binding.playlistGroupTabs.visibility =
            if (!collapsed && selectedTab == RadioTab.PLAYLISTS) View.VISIBLE else View.GONE
        binding.rvCategories.visibility =
            if (!collapsed && selectedTab == RadioTab.PLAYLISTS) View.VISIBLE else View.GONE
    }

    private fun setupTabs() {
        binding.tabLayout.apply {
            addTab(newTab().setText(R.string.radio_tab_rankings), selectedTab == RadioTab.RANKINGS)
            addTab(newTab().setText(R.string.radio_tab_playlists), selectedTab == RadioTab.PLAYLISTS)
            addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
                override fun onTabSelected(tab: TabLayout.Tab) {
                    selectTab(if (tab.position == 0) RadioTab.RANKINGS else RadioTab.PLAYLISTS)
                }

                override fun onTabUnselected(tab: TabLayout.Tab) = Unit

                override fun onTabReselected(tab: TabLayout.Tab) {
                    binding.recyclerView.smoothScrollToPosition(0)
                }
            })
        }
    }

    private fun setupInteractions() {
    }

    private fun setupSearch() {
        binding.etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                renderFiltered(s?.toString().orEmpty())
            }
            override fun afterTextChanged(s: Editable?) = Unit
        })
    }

    private fun setupObservers() {
        musicViewModel.playlistCategories.observe(viewLifecycleOwner) { categories ->
            val distinct = categories.distinctBy { it.apiName }
            rebuildGroupTabs(distinct)
            categoryAdapter.submitList(categoriesForSelectedGroup(distinct))
            categoryAdapter.selectedApiName = selectedCategory
        }
        musicViewModel.topLists.observe(viewLifecycleOwner) {
            rankingsLoaded = true
            if (selectedTab == RadioTab.RANKINGS) render(it)
        }
        musicViewModel.topPlaylists.observe(viewLifecycleOwner) {
            playlistsLoaded = true
            if (loadingMore) {
                loadingMore = false
                if (it.size <= previousPlaylistCount || it.size - previousPlaylistCount < PLAYLIST_PAGE_SIZE) {
                    hasMorePlaylists = false
                }
            }
            if (selectedTab == RadioTab.PLAYLISTS) render(it)
        }
        musicViewModel.error.observe(viewLifecycleOwner) { message ->
            val text = message?.trim().orEmpty()
            if (text.isBlank()) return@observe
            if (selectedTab == RadioTab.RANKINGS) rankingsLoaded = true else playlistsLoaded = true
            render(emptyList())
            Toast.makeText(requireContext(), text, Toast.LENGTH_SHORT).show()
        }
    }

    private fun selectTab(tab: RadioTab, forceRefresh: Boolean = false) {
        selectedTab = tab
        val supportsCategories = MusicSourcePreferences.activeSource(requireContext()) ==
            MusicSourcePreferences.Source.NETEASE
        if (!supportsCategories) selectedCategory = ""
        binding.rvCategories.visibility =
            if (!radioHeaderCollapsed && tab == RadioTab.PLAYLISTS && supportsCategories) View.VISIBLE else View.GONE
        val categoryVisibility =
            if (!radioHeaderCollapsed && tab == RadioTab.PLAYLISTS && supportsCategories) View.VISIBLE else View.GONE
        binding.tvPlaylistCategoryLabel.visibility = categoryVisibility
        binding.playlistGroupTabs.visibility = categoryVisibility
        if (tab == RadioTab.PLAYLISTS && supportsCategories &&
            musicViewModel.playlistCategories.value.orEmpty().size <= 1
        ) {
            musicViewModel.loadPlaylistCategories()
        }
        binding.etSearch.setText("")
        binding.etSearch.setHint(
            if (tab == RadioTab.RANKINGS) R.string.radio_search_rankings else R.string.radio_search_playlists
        )
        binding.tvEmpty.setText(
            if (tab == RadioTab.RANKINGS) R.string.radio_empty_rankings else R.string.radio_empty_playlists
        )
        val current = if (tab == RadioTab.RANKINGS) {
            musicViewModel.topLists.value.orEmpty()
        } else {
            musicViewModel.topPlaylists.value.orEmpty()
        }

        val hasFinishedLoading = if (tab == RadioTab.RANKINGS) rankingsLoaded else playlistsLoaded
        if (!forceRefresh && (current.isNotEmpty() || hasFinishedLoading)) {
            render(current)
            return
        }

        adapter.submitList(emptyList())
        startLoading()
        when (tab) {
            RadioTab.RANKINGS -> {
                if (!rankingsRequested || forceRefresh) {
                    rankingsRequested = true
                    rankingsLoaded = false
                    musicViewModel.loadTopLists(forceRefresh = forceRefresh)
                }
            }
            RadioTab.PLAYLISTS -> {
                if (!playlistsRequested || forceRefresh) {
                    playlistsRequested = true
                    playlistsLoaded = false
                    musicViewModel.loadTopPlaylists(
                        category = selectedCategory,
                        limit = PLAYLIST_PAGE_SIZE,
                        forceRefresh = forceRefresh
                    )
                }
            }
        }
    }

    private fun refreshCurrentTab() {
        selectTab(selectedTab, forceRefresh = true)
    }

    private fun selectCategory(category: PlaylistCategory) {
        if (category.apiName == selectedCategory) return
        selectedCategory = category.apiName
        categoryAdapter.selectedApiName = selectedCategory
        playlistsRequested = true
        playlistsLoaded = false
        loadingMore = false
        hasMorePlaylists = true
        previousPlaylistCount = 0
        adapter.submitList(emptyList())
        startLoading()
        musicViewModel.loadTopPlaylists(category = selectedCategory)
    }

    private fun rebuildGroupTabs(categories: List<PlaylistCategory>) {
        val groups = buildList {
            add(null)
            categories.mapNotNull { it.groupId }
                .distinct()
                .forEach { add(it) }
        }
        groupTabIds = groups
        rebuildingGroupTabs = true
        binding.playlistGroupTabs.removeAllTabs()
        groups.forEach { groupId ->
            val title = if (groupId == null) {
                getString(R.string.playlist_category_all)
            } else {
                categories.firstOrNull { it.groupId == groupId }?.groupName.orEmpty()
            }
            binding.playlistGroupTabs.addTab(
                binding.playlistGroupTabs.newTab().setText(title),
                groupId == selectedGroupId
            )
        }
        rebuildingGroupTabs = false
    }

    private fun categoriesForSelectedGroup(categories: List<PlaylistCategory>): List<PlaylistCategory> {
        return if (selectedGroupId == null) categories else categories.filter {
            it.groupId == selectedGroupId
        }
    }

    private fun selectCategoryGroup(groupId: Int?) {
        if (groupId == selectedGroupId) return
        selectedGroupId = groupId
        val categories = musicViewModel.playlistCategories.value.orEmpty()
        val visibleCategories = categoriesForSelectedGroup(categories)
        categoryAdapter.submitList(visibleCategories)
        val nextCategory = visibleCategories
            .firstOrNull { it.hot }
            ?: visibleCategories.firstOrNull()
            ?: PlaylistCategory.All
        selectedCategory = nextCategory.apiName
        categoryAdapter.selectedApiName = selectedCategory
        playlistsRequested = true
        playlistsLoaded = false
        loadingMore = false
        hasMorePlaylists = true
        previousPlaylistCount = 0
        adapter.submitList(emptyList())
        startLoading()
        musicViewModel.loadTopPlaylists(category = selectedCategory)
    }

    private fun render(playlists: List<Playlist>) {
        allItems = playlists
        renderFiltered(binding.etSearch.text?.toString().orEmpty())
        stopLoading()
    }

    private fun renderFiltered(query: String) {
        val normalized = query.trim()
        val filtered = if (normalized.isBlank()) {
            allItems
        } else {
            allItems.filter { it.name.contains(normalized, ignoreCase = true) }
        }
        adapter.submitList(filtered)
        binding.tvEmpty.visibility = if (filtered.isEmpty()) View.VISIBLE else View.GONE
        binding.recyclerView.visibility = if (filtered.isEmpty()) View.GONE else View.VISIBLE
    }

    private fun startLoading() {
        binding.tvEmpty.visibility = View.GONE
        binding.recyclerView.visibility = View.VISIBLE
        binding.progressBar.visibility = View.VISIBLE
    }

    private fun stopLoading() {
        binding.progressBar.visibility = View.GONE
    }

    private fun openPlaylist(playlist: Playlist) {
        // Rankings carry their own display name (for example 飙升榜、新歌榜、热歌榜).
        // Keep a fallback only for malformed source data.
        val detailTitle = playlist.name.ifBlank { "飙升榜" }
        val fragment = PlaylistSongsFragment.newInstance(playlist.id, detailTitle)
        val main = activity as? com.music.player.MainActivity
        if (main != null) {
            main.pushDetail(fragment)
        } else {
            parentFragmentManager.beginTransaction()
                .replace(R.id.fragmentContainer, fragment)
                .addToBackStack(null)
                .commit()
        }
    }

}
