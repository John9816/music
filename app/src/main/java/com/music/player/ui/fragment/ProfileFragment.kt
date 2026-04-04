package com.music.player.ui.fragment

import android.app.Activity
import android.content.Intent
import android.net.Uri
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
import com.music.player.data.model.Song
import com.music.player.databinding.FragmentProfileBinding
import com.music.player.ui.activity.SettingsActivity
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.resolveThemeColor
import com.music.player.ui.util.resolveThemeColorStateList
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.LibraryViewModel

class ProfileFragment : Fragment(), RootTabInteraction {

    private var _binding: FragmentProfileBinding? = null
    private val binding: FragmentProfileBinding
        get() = _binding!!

    private lateinit var authViewModel: AuthViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private var currentUser: UserProfile? = null
    private var awaitingUserRefresh: Boolean = false
    private var awaitingFavoritesRefresh: Boolean = false
    private var awaitingHistoryRefresh: Boolean = false

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

        binding.layoutHeroContent.applyStatusBarInsetPadding()
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

    override fun onTabReselected() {
        val binding = _binding ?: return
        if (binding.scrollContent.scrollY > 0) {
            binding.scrollContent.smoothScrollTo(0, 0)
            return
        }
        refresh(userInitiated = true)
    }

    private fun refresh() {
        refresh(userInitiated = false)
    }

    private fun refresh(userInitiated: Boolean) {
        if (userInitiated) {
            awaitingUserRefresh = true
            awaitingFavoritesRefresh = true
            awaitingHistoryRefresh = true
            binding.swipeRefresh.isRefreshing = true
            binding.swipeRefresh.postDelayed({
                if (_binding != null && binding.swipeRefresh.isRefreshing) {
                    stopRefreshIndicator()
                }
            }, 3000L)
        }
        authViewModel.refreshProfile()
        libraryViewModel.refreshFavorites(silent = true)
        libraryViewModel.refreshHistory()
    }

    private fun setupUi() {
        binding.swipeRefresh.setColorSchemeColors(requireContext().resolveThemeColor(R.attr.brandPrimary))
        binding.swipeRefresh.setOnRefreshListener { refresh(userInitiated = true) }
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
            awaitingUserRefresh = false
            syncRefreshState()
        }

        libraryViewModel.favorites.observe(viewLifecycleOwner) { songs ->
            updateLikedSection(songs)
            awaitingFavoritesRefresh = false
            syncRefreshState()
        }

        libraryViewModel.history.observe(viewLifecycleOwner) { songs ->
            updateHistorySection(songs)
            awaitingHistoryRefresh = false
            syncRefreshState()
        }
    }

    private fun updateLikedSection(songs: List<Song>) {
        updateLikedCover(songs.firstOrNull()?.album?.picUrl)
        binding.tvLikedMeta.text = if (songs.isEmpty()) {
            getString(R.string.profile_liked_empty)
        } else {
            getString(R.string.profile_liked_meta, songs.size, describeSong(songs.first()))
        }
    }

    private fun updateHistorySection(songs: List<Song>) {
        updateHistoryCover(songs.firstOrNull()?.album?.picUrl)
        binding.tvHistoryMeta.text = if (songs.isEmpty()) {
            getString(R.string.profile_history_empty)
        } else {
            getString(R.string.profile_history_meta, songs.size, describeSong(songs.first()))
        }
    }

    private fun describeSong(song: Song): String {
        val artists = song.artists
            .map { it.name.trim() }
            .filter { it.isNotBlank() }
            .distinct()

        return if (artists.isEmpty()) {
            song.name
        } else {
            getString(R.string.profile_song_meta, song.name, artists.joinToString(" / "))
        }
    }

    private fun updateLikedCover(coverUrl: String?) {
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            binding.ivLikedCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivLikedCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
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
            binding.ivHistoryCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
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
        binding.tvNickname.text = user.nickname?.takeIf { it.isNotBlank() }
            ?: user.username?.takeIf { it.isNotBlank() }
            ?: user.email?.substringBefore("@")
            ?: getString(R.string.profile_nickname_placeholder)
        binding.tvSignature.text = user.signature?.takeIf { it.isNotBlank() }
            ?: getString(R.string.profile_signature_empty)
        binding.tvProfileMeta.text = buildProfileMeta(user)

        binding.ivAvatar.setPadding(0, 0, 0, 0)
        binding.ivAvatar.imageTintList = null
        Glide.with(binding.ivAvatar)
            .load(resolveAvatarUrl(user))
            .placeholder(R.drawable.ic_person_24)
            .error(R.drawable.ic_person_24)
            .circleCrop()
            .into(binding.ivAvatar)

        if (!user.badge.isNullOrEmpty()) {
            binding.tvBadge.text = getString(R.string.profile_badge, user.badge)
            binding.tvBadge.visibility = View.VISIBLE
        } else {
            binding.tvBadge.visibility = View.GONE
        }
    }

    private fun syncRefreshState() {
        if (awaitingUserRefresh || awaitingFavoritesRefresh || awaitingHistoryRefresh) return
        stopRefreshIndicator()
    }

    private fun stopRefreshIndicator() {
        awaitingUserRefresh = false
        awaitingFavoritesRefresh = false
        awaitingHistoryRefresh = false
        binding.swipeRefresh.isRefreshing = false
    }

    private fun buildProfileMeta(user: UserProfile): String {
        val primary = user.email?.trim().orEmpty()
            .ifBlank { user.username?.trim().orEmpty() }
            .ifBlank { user.nickname?.trim().orEmpty() }
            .ifBlank { getString(R.string.profile_account_placeholder) }

        val shortId = user.id.takeLast(6).uppercase()
        return getString(R.string.profile_account_meta, primary, shortId)
    }

    private fun resolveAvatarUrl(user: UserProfile): String {
        val direct = user.avatar_url?.trim().orEmpty()
        if (direct.isNotBlank()) return direct

        val seed = user.nickname?.trim().orEmpty()
            .ifBlank { user.username?.trim().orEmpty() }
            .ifBlank { user.email?.trim().orEmpty() }
            .ifBlank { user.id }

        return "https://api.dicebear.com/9.x/initials/png?seed=${Uri.encode(seed)}&radius=50&backgroundType=gradientLinear"
    }
}
