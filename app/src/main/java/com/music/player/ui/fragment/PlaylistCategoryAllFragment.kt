package com.music.player.ui.fragment

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.music.player.R
import com.music.player.databinding.FragmentPlaylistCategoryAllBinding
import com.music.player.ui.adapter.PlaylistGridAdapter
import com.music.player.ui.viewmodel.PlaylistCategoryAllViewModel

class PlaylistCategoryAllFragment : Fragment() {

    companion object {
        private const val ARG_TITLE = "title"
        private const val ARG_CATEGORY = "category"

        fun newInstance(title: String, category: String): PlaylistCategoryAllFragment =
            PlaylistCategoryAllFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_TITLE, title)
                    putString(ARG_CATEGORY, category)
                }
            }
    }

    private var _binding: FragmentPlaylistCategoryAllBinding? = null
    private val binding: FragmentPlaylistCategoryAllBinding
        get() = _binding!!

    private lateinit var viewModel: PlaylistCategoryAllViewModel
    private lateinit var adapter: PlaylistGridAdapter

    private val titleText: String
        get() = arguments?.getString(ARG_TITLE).orEmpty()

    private val category: String
        get() = arguments?.getString(ARG_CATEGORY).orEmpty()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPlaylistCategoryAllBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        viewModel = ViewModelProvider(this)[PlaylistCategoryAllViewModel::class.java]
        binding.tvPlaylistCategoryTitle.text = titleText.ifBlank {
            category.ifBlank { getString(R.string.nav_playlists) }
        }

        adapter = PlaylistGridAdapter { playlist ->
            parentFragmentManager.beginTransaction()
                .replace(R.id.fragmentContainer, PlaylistSongsFragment.newInstance(playlist.id))
                .addToBackStack(null)
                .commit()
        }

        val grid = GridLayoutManager(requireContext(), 2)
        binding.recyclerView.layoutManager = grid
        binding.recyclerView.adapter = adapter
        binding.recyclerView.setHasFixedSize(true)
        binding.recyclerView.itemAnimator = null

        binding.recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy <= 0) return
                val lastVisible = grid.findLastVisibleItemPosition()
                val total = grid.itemCount
                if (total <= 0) return
                if (lastVisible >= total - 6) {
                    viewModel.loadMore(limit = 42)
                }
            }
        })

        viewModel.playlists.observe(viewLifecycleOwner) { playlists ->
            adapter.submitList(playlists)
            val isEmpty = playlists.isEmpty()
            binding.tvEmpty.visibility = if (isEmpty) View.VISIBLE else View.GONE
            binding.recyclerView.visibility = if (isEmpty) View.GONE else View.VISIBLE
        }

        viewModel.isLoading.observe(viewLifecycleOwner) { loading ->
            binding.progressBar.visibility = if (loading == true) View.VISIBLE else View.GONE
        }

        viewModel.error.observe(viewLifecycleOwner) { msg ->
            val text = msg?.trim().orEmpty()
            if (text.isBlank()) return@observe
            Toast.makeText(requireContext(), text, Toast.LENGTH_SHORT).show()
        }

        if (category.isBlank()) {
            binding.tvEmpty.visibility = View.VISIBLE
            binding.recyclerView.visibility = View.GONE
            binding.tvEmpty.text = getString(R.string.toplist_empty)
            return
        }

        viewModel.resetAndLoad(category = category, limit = 42, autoPrefetchNextPage = true)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
