package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.music.player.R
import com.music.player.data.model.Playlist
import com.music.player.data.model.PlaylistCategory
import com.music.player.databinding.FragmentPlaylistsBinding
import com.music.player.ui.adapter.PlaylistAdapter
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.viewmodel.LibraryViewModel
import com.music.player.ui.viewmodel.MusicViewModel

class PlaylistsFragment : Fragment(), RootTabInteraction {

    private var _binding: FragmentPlaylistsBinding? = null
    private val binding: FragmentPlaylistsBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var libraryViewModel: LibraryViewModel

    private lateinit var langAdapter: PlaylistAdapter
    private lateinit var styleAdapter: PlaylistAdapter
    private lateinit var sceneAdapter: PlaylistAdapter
    private lateinit var emotionAdapter: PlaylistAdapter
    private lateinit var themeAdapter: PlaylistAdapter
    private var langCat: String = ""
    private var styleCat: String = ""
    private var sceneCat: String = ""
    private var emotionCat: String = ""
    private var themeCat: String = ""
    private val groupLoaded = BooleanArray(5)
    private var categoriesReady: Boolean = false
    private var isLangLoading: Boolean = false
    private var isStyleLoading: Boolean = false
    private var isSceneLoading: Boolean = false
    private var isEmotionLoading: Boolean = false
    private var isThemeLoading: Boolean = false
    private var isUserRefreshing: Boolean = false

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPlaylistsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        binding.layoutHeroContent.applyStatusBarInsetPadding()
        setupUi()
        setupObservers()
        setupInteractions()

        libraryViewModel.prefetch()
        musicViewModel.loadPlaylistCategories()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    override fun onTabReselected() {
        val binding = _binding ?: return
        if (binding.scrollView.scrollY > 0) {
            binding.scrollView.smoothScrollTo(0, 0)
            return
        }
        refreshContent(userInitiated = true)
    }

    private fun setupUi() {
        binding.tvLangTitle.setOnClickListener { openGroup(groupId = 0, titleRes = R.string.playlist_group_language) }
        binding.tvStyleTitle.setOnClickListener { openGroup(groupId = 1, titleRes = R.string.playlist_group_style) }
        binding.tvSceneTitle.setOnClickListener { openGroup(groupId = 2, titleRes = R.string.playlist_group_scene) }
        binding.tvEmotionTitle.setOnClickListener { openGroup(groupId = 3, titleRes = R.string.playlist_group_emotion) }
        binding.tvThemeTitle.setOnClickListener { openGroup(groupId = 4, titleRes = R.string.playlist_group_theme) }
        binding.scrollView.setOnScrollChangeListener { _: View, _: Int, _: Int, _: Int, _: Int ->
            maybeLoadVisibleSections()
        }

        fun openPlaylist(playlist: Playlist) {
            parentFragmentManager.beginTransaction()
                .replace(R.id.fragmentContainer, PlaylistSongsFragment.newInstance(playlist.id))
                .addToBackStack(null)
                .commit()
        }

        langAdapter = PlaylistAdapter(::openPlaylist)
        styleAdapter = PlaylistAdapter(::openPlaylist)
        sceneAdapter = PlaylistAdapter(::openPlaylist)
        emotionAdapter = PlaylistAdapter(::openPlaylist)
        themeAdapter = PlaylistAdapter(::openPlaylist)

        binding.rvLangPlaylists.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false).apply {
                initialPrefetchItemCount = 6
            }
            adapter = langAdapter
            setHasFixedSize(true)
            setItemViewCacheSize(8)
            itemAnimator = null
        }
        binding.rvStylePlaylists.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false).apply {
                initialPrefetchItemCount = 6
            }
            adapter = styleAdapter
            setHasFixedSize(true)
            setItemViewCacheSize(8)
            itemAnimator = null
        }
        binding.rvScenePlaylists.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false).apply {
                initialPrefetchItemCount = 6
            }
            adapter = sceneAdapter
            setHasFixedSize(true)
            setItemViewCacheSize(8)
            itemAnimator = null
        }
        binding.rvEmotionPlaylists.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false).apply {
                initialPrefetchItemCount = 6
            }
            adapter = emotionAdapter
            setHasFixedSize(true)
            setItemViewCacheSize(8)
            itemAnimator = null
        }
        binding.rvThemePlaylists.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false).apply {
                initialPrefetchItemCount = 6
            }
            adapter = themeAdapter
            setHasFixedSize(true)
            setItemViewCacheSize(8)
            itemAnimator = null
        }
    }

    private fun setupInteractions() {
        binding.swipeRefresh.setColorSchemeColors(requireContext().resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener {
            refreshContent(userInitiated = true)
        }
    }

    private fun setupObservers() {
        musicViewModel.languageLoading.observe(viewLifecycleOwner) { loading ->
            isLangLoading = loading == true
            binding.pbLang.visibility = if (loading == true) View.VISIBLE else View.GONE
            syncRefreshState()
        }
        musicViewModel.styleLoading.observe(viewLifecycleOwner) { loading ->
            isStyleLoading = loading == true
            binding.pbStyle.visibility = if (loading == true) View.VISIBLE else View.GONE
            syncRefreshState()
        }
        musicViewModel.sceneLoading.observe(viewLifecycleOwner) { loading ->
            isSceneLoading = loading == true
            binding.pbScene.visibility = if (loading == true) View.VISIBLE else View.GONE
            syncRefreshState()
        }
        musicViewModel.emotionLoading.observe(viewLifecycleOwner) { loading ->
            isEmotionLoading = loading == true
            binding.pbEmotion.visibility = if (loading == true) View.VISIBLE else View.GONE
            syncRefreshState()
        }
        musicViewModel.themeLoading.observe(viewLifecycleOwner) { loading ->
            isThemeLoading = loading == true
            binding.pbTheme.visibility = if (loading == true) View.VISIBLE else View.GONE
            syncRefreshState()
        }

        musicViewModel.languagePlaylists.observe(viewLifecycleOwner) { langAdapter.submitList(it) }
        musicViewModel.stylePlaylists.observe(viewLifecycleOwner) { styleAdapter.submitList(it) }
        musicViewModel.scenePlaylists.observe(viewLifecycleOwner) { sceneAdapter.submitList(it) }
        musicViewModel.emotionPlaylists.observe(viewLifecycleOwner) { emotionAdapter.submitList(it) }
        musicViewModel.themePlaylists.observe(viewLifecycleOwner) { themeAdapter.submitList(it) }

        musicViewModel.playlistCategories.observe(viewLifecycleOwner) { categories ->
            langCat = pickDefaultCategory(categories, groupId = 0)
            styleCat = pickDefaultCategory(categories, groupId = 1)
            sceneCat = pickDefaultCategory(categories, groupId = 2)
            emotionCat = pickDefaultCategory(categories, groupId = 3)
            themeCat = pickDefaultCategory(categories, groupId = 4)

            binding.tvLangTitle.text = titleWithPicked(R.string.playlist_group_language, langCat)
            binding.tvStyleTitle.text = titleWithPicked(R.string.playlist_group_style, styleCat)
            binding.tvSceneTitle.text = titleWithPicked(R.string.playlist_group_scene, sceneCat)
            binding.tvEmotionTitle.text = titleWithPicked(R.string.playlist_group_emotion, emotionCat)
            binding.tvThemeTitle.text = titleWithPicked(R.string.playlist_group_theme, themeCat)

            categoriesReady = true
            for (i in groupLoaded.indices) groupLoaded[i] = false
            binding.scrollView.post { maybeLoadVisibleSections() }
            syncRefreshState()
        }

        musicViewModel.error.observe(viewLifecycleOwner) { msg ->
            val text = msg?.trim().orEmpty()
            if (text.isBlank()) return@observe
            Toast.makeText(requireContext(), text, Toast.LENGTH_SHORT).show()
        }
    }

    private fun refreshContent(userInitiated: Boolean) {
        categoriesReady = false
        for (i in groupLoaded.indices) groupLoaded[i] = false
        if (userInitiated) {
            isUserRefreshing = true
            binding.swipeRefresh.isRefreshing = true
            binding.swipeRefresh.postDelayed({
                if (_binding != null && isUserRefreshing) {
                    stopRefreshIndicator()
                }
            }, 3000L)
        }
        musicViewModel.loadPlaylistCategories()
    }

    private fun pickDefaultCategory(all: List<PlaylistCategory>, groupId: Int): String {
        val inGroup = all.filter { it.groupId == groupId && it.apiName.isNotBlank() }
        val hot = inGroup.firstOrNull { it.hot }?.apiName
        return hot ?: inGroup.firstOrNull()?.apiName ?: ""
    }

    private fun titleWithPicked(titleRes: Int, pickedCategory: String): String {
        val title = getString(titleRes)
        val cat = pickedCategory.trim()
        return if (cat.isBlank()) title else "$title · $cat"
    }

    private fun openGroup(groupId: Int, titleRes: Int) {
        val fragment = PlaylistGroupFragment.newInstance(groupId = groupId, groupTitle = getString(titleRes))
        val main = activity as? com.music.player.MainActivity
        if (main != null) {
            main.pushDetail(fragment)
        } else {
            parentFragmentManager.beginTransaction()
                .add(R.id.fragmentContainer, fragment)
                .addToBackStack(null)
                .commit()
        }
    }

    private fun maybeLoadVisibleSections() {
        if (!categoriesReady) return
        val scrollView = binding.scrollView
        val preloadPx = (240f * resources.displayMetrics.density).toInt()
        val viewportBottom = scrollView.scrollY + scrollView.height + preloadPx

        fun shouldLoad(view: View): Boolean = view.top <= viewportBottom

        if (!groupLoaded[0] && shouldLoad(binding.rvLangPlaylists)) {
            groupLoaded[0] = true
            musicViewModel.loadGroupPlaylists(groupId = 0, category = langCat, limit = 12)
        }
        if (!groupLoaded[1] && shouldLoad(binding.rvStylePlaylists)) {
            groupLoaded[1] = true
            musicViewModel.loadGroupPlaylists(groupId = 1, category = styleCat, limit = 12)
        }
        if (!groupLoaded[2] && shouldLoad(binding.rvScenePlaylists)) {
            groupLoaded[2] = true
            musicViewModel.loadGroupPlaylists(groupId = 2, category = sceneCat, limit = 12)
        }
        if (!groupLoaded[3] && shouldLoad(binding.rvEmotionPlaylists)) {
            groupLoaded[3] = true
            musicViewModel.loadGroupPlaylists(groupId = 3, category = emotionCat, limit = 12)
        }
        if (!groupLoaded[4] && shouldLoad(binding.rvThemePlaylists)) {
            groupLoaded[4] = true
            musicViewModel.loadGroupPlaylists(groupId = 4, category = themeCat, limit = 12)
        }
    }

    private fun syncRefreshState() {
        if (!isUserRefreshing) return
        val anySectionLoading = isLangLoading || isStyleLoading || isSceneLoading || isEmotionLoading || isThemeLoading
        if (!categoriesReady || anySectionLoading) return
        stopRefreshIndicator()
    }

    private fun stopRefreshIndicator() {
        isUserRefreshing = false
        binding.swipeRefresh.isRefreshing = false
    }
}
