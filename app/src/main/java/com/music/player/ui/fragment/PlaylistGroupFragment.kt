package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.music.player.R
import com.music.player.data.model.PlaylistCategory
import com.music.player.databinding.FragmentPlaylistGroupBinding
import com.music.player.ui.adapter.PlaylistCategoryChipAdapter
import com.music.player.ui.adapter.PlaylistGridAdapter
import com.music.player.ui.viewmodel.MusicViewModel
import com.music.player.ui.viewmodel.PlaylistCategoryAllViewModel

class PlaylistGroupFragment : Fragment() {

    companion object {
        private const val ARG_GROUP_ID = "group_id"
        private const val ARG_GROUP_TITLE = "group_title"

        fun newInstance(groupId: Int, groupTitle: String): PlaylistGroupFragment =
            PlaylistGroupFragment().apply {
                arguments = Bundle().apply {
                    putInt(ARG_GROUP_ID, groupId)
                    putString(ARG_GROUP_TITLE, groupTitle)
                }
            }
    }

    private var _binding: FragmentPlaylistGroupBinding? = null
    private val binding: FragmentPlaylistGroupBinding
        get() = _binding!!

    private lateinit var musicViewModel: MusicViewModel
    private lateinit var listViewModel: PlaylistCategoryAllViewModel

    private lateinit var categoryAdapter: PlaylistCategoryChipAdapter
    private lateinit var playlistAdapter: PlaylistGridAdapter

    private val groupId: Int
        get() = arguments?.getInt(ARG_GROUP_ID) ?: 0

    private val groupTitle: String
        get() = arguments?.getString(ARG_GROUP_TITLE).orEmpty()

    private var selectedCategory: PlaylistCategory? = null

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPlaylistGroupBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        musicViewModel = ViewModelProvider(requireActivity())[MusicViewModel::class.java]
        listViewModel = ViewModelProvider(this)[PlaylistCategoryAllViewModel::class.java]
        binding.tvPlaylistPageTitle.text = groupTitle.ifBlank { getString(R.string.nav_playlists) }

        categoryAdapter = PlaylistCategoryChipAdapter { category ->
            if (category.apiName.isBlank()) return@PlaylistCategoryChipAdapter
            if (selectedCategory?.apiName == category.apiName) return@PlaylistCategoryChipAdapter
            selectCategory(category)
        }
        binding.rvCategories.apply {
            layoutManager = LinearLayoutManager(requireContext(), LinearLayoutManager.HORIZONTAL, false)
            adapter = categoryAdapter
            setHasFixedSize(true)
            itemAnimator = null
        }

        playlistAdapter = PlaylistGridAdapter { playlist ->
            parentFragmentManager.beginTransaction()
                .replace(R.id.fragmentContainer, PlaylistSongsFragment.newInstance(playlist.id))
                .addToBackStack(null)
                .commit()
        }
        val grid = GridLayoutManager(requireContext(), 2)
        binding.recyclerView.layoutManager = grid
        binding.recyclerView.adapter = playlistAdapter
        binding.recyclerView.setHasFixedSize(true)
        binding.recyclerView.itemAnimator = null
        binding.recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy <= 0) return
                val lastVisible = grid.findLastVisibleItemPosition()
                val total = grid.itemCount
                if (total <= 0) return
                if (lastVisible >= total - 6) {
                    listViewModel.loadMore(limit = 42)
                }
            }
        })

        musicViewModel.playlistCategories.observe(viewLifecycleOwner) { categories ->
            val inGroup = categories
                .filter { it.groupId == groupId && it.apiName.isNotBlank() }
                .distinctBy { it.apiName }
            categoryAdapter.submitList(inGroup)

            if (selectedCategory == null) {
                val picked = inGroup.firstOrNull { it.hot } ?: inGroup.firstOrNull()
                picked?.let { selectCategory(it) }
            } else if (inGroup.none { it.apiName == selectedCategory?.apiName }) {
                selectedCategory = null
            }
        }

        listViewModel.playlists.observe(viewLifecycleOwner) { playlists ->
            playlistAdapter.submitList(playlists)
            val isEmpty = playlists.isEmpty()
            binding.tvEmpty.visibility = if (isEmpty) View.VISIBLE else View.GONE
            binding.recyclerView.visibility = if (isEmpty) View.GONE else View.VISIBLE
        }

        listViewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            binding.progressBar.visibility = if (loading == true) View.VISIBLE else View.GONE
        }

        listViewModel.error.observe(viewLifecycleOwner) { msg ->
            val text = msg?.trim().orEmpty()
            if (text.isBlank()) return@observe
            Toast.makeText(requireContext(), text, Toast.LENGTH_SHORT).show()
        }

        if (musicViewModel.playlistCategories.value.isNullOrEmpty()) {
            musicViewModel.loadPlaylistCategories()
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun selectCategory(category: PlaylistCategory) {
        selectedCategory = category
        categoryAdapter.selectedApiName = category.apiName
        listViewModel.resetAndLoad(category = category.apiName, limit = 42, autoPrefetchNextPage = true)
    }
}
