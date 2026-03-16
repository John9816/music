package com.music.player.ui.fragment

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.databinding.FragmentProfileBinding
import com.music.player.ui.activity.SettingsActivity
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.LibraryViewModel

class ProfileFragment : Fragment() {

    private var _binding: FragmentProfileBinding? = null
    private val binding: FragmentProfileBinding
        get() = _binding!!

    private lateinit var authViewModel: AuthViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private var currentUser: UserProfile? = null

    private val settingsLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val shouldRecreate = result.resultCode == Activity.RESULT_OK &&
                result.data?.getBooleanExtra(SettingsActivity.EXTRA_SHOULD_RECREATE_MAIN, false) == true
            if (shouldRecreate) {
                requireActivity().recreate()
            }
        }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentProfileBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        authViewModel = ViewModelProvider(requireActivity())[AuthViewModel::class.java]
        libraryViewModel = ViewModelProvider(requireActivity())[LibraryViewModel::class.java]

        binding.scrollContent.applyStatusBarInsetPadding()

        setupUi()
        setupObservers()
        refresh()
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun refresh() {
        authViewModel.refreshProfile()
        libraryViewModel.refreshFavorites(silent = true)
        libraryViewModel.refreshHistory()
    }

    private fun setupUi() {
        binding.btnSettings.setOnClickListener {
            settingsLauncher.launch(Intent(requireContext(), SettingsActivity::class.java))
        }

        val openLiked = View.OnClickListener { openCollection(SongCollectionFragment.newLiked()) }
        val openHistory = View.OnClickListener { openCollection(SongCollectionFragment.newHistory()) }
        binding.rowLiked.setOnClickListener(openLiked)
        binding.tvLikedTitle.setOnClickListener(openLiked)
        binding.rowHistory.setOnClickListener(openHistory)
        binding.tvHistoryTitle.setOnClickListener(openHistory)
    }

    private fun openCollection(fragment: Fragment) {
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

    private fun setupObservers() {
        authViewModel.currentUser.observe(viewLifecycleOwner) { user ->
            currentUser = user
            renderUser(user)
        }

        libraryViewModel.favorites.observe(viewLifecycleOwner) { songs ->
            updateLikedCover(songs.firstOrNull()?.album?.picUrl)
        }

        libraryViewModel.history.observe(viewLifecycleOwner) { songs ->
            updateHistoryCover(songs.firstOrNull()?.album?.picUrl)
        }
    }

    private fun updateLikedCover(coverUrl: String?) {
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            binding.ivLikedCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivLikedCover.imageTintList =
                ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
        } else {
            binding.ivLikedCover.imageTintList = null
            Glide.with(binding.ivLikedCover)
                .load(url)
                .placeholder(R.drawable.ic_music_note_24)
                .centerCrop()
                .into(binding.ivLikedCover)
        }
    }

    private fun updateHistoryCover(coverUrl: String?) {
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            binding.ivHistoryCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHistoryCover.imageTintList =
                ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
        } else {
            binding.ivHistoryCover.imageTintList = null
            Glide.with(binding.ivHistoryCover)
                .load(url)
                .placeholder(R.drawable.ic_music_note_24)
                .centerCrop()
                .into(binding.ivHistoryCover)
        }
    }

    private fun renderUser(user: UserProfile?) {
        user ?: return
        binding.tvEmail.text = user.email ?: getString(R.string.profile_email_placeholder)

        val avatarUrl = user.avatar_url?.trim().orEmpty()
        if (avatarUrl.isBlank()) {
            val paddingPx = (22f * resources.displayMetrics.density).toInt()
            binding.ivAvatar.setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
            binding.ivAvatar.imageTintList =
                ColorStateList.valueOf(requireContext().getColor(R.color.brand_primary))
            binding.ivAvatar.setImageResource(R.drawable.ic_person_24)
        } else {
            binding.ivAvatar.setPadding(0, 0, 0, 0)
            binding.ivAvatar.imageTintList = null
            Glide.with(binding.ivAvatar)
                .load(avatarUrl)
                .placeholder(R.drawable.ic_person_24)
                .error(R.drawable.ic_person_24)
                .circleCrop()
                .into(binding.ivAvatar)
        }

        if (!user.badge.isNullOrEmpty()) {
            binding.tvBadge.text = getString(R.string.profile_badge, user.badge)
            binding.tvBadge.visibility = View.VISIBLE
        } else {
            binding.tvBadge.visibility = View.GONE
        }
    }
}
