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
import com.music.player.ui.util.resolveThemeColor
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
        categoryAdapter.selectedApiName = ""
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
        }
    }

    private fun setupCategories() {
        categoryAdapter = PlaylistCategoryChipAdapter(
            showGroupName = true,
            onClick = ::selectCategory
        )
        binding.rvCategories.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
            adapter = categoryAdapter
            itemAnimator = null
        }
        categoryAdapter.selectedApiName = selectedCategory
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
        binding.swipeRefresh.setColorSchemeColors(requireContext().resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener { refreshCurrentTab() }
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
            categoryAdapter.submitList(categories.distinctBy { it.apiName })
            categoryAdapter.selectedApiName = selectedCategory
        }
        musicViewModel.topLists.observe(viewLifecycleOwner) {
            rankingsLoaded = true
            if (selectedTab == RadioTab.RANKINGS) render(it)
        }
        musicViewModel.topPlaylists.observe(viewLifecycleOwner) {
            playlistsLoaded = true
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
            if (tab == RadioTab.PLAYLISTS && supportsCategories) View.VISIBLE else View.GONE
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
        binding.swipeRefresh.isRefreshing = false
        binding.progressBar.visibility = View.GONE
    }

    private fun openPlaylist(playlist: Playlist) {
        val fragment = PlaylistSongsFragment.newInstance(playlist.id)
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

    private companion object {
        const val STATE_TAB = "radio_selected_tab"
        const val STATE_CATEGORY = "radio_playlist_category"
    }
}
