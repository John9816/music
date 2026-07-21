package com.music.player.ui.fragment

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import com.music.player.databinding.FragmentProfileBinding
import com.music.player.ui.activity.SettingsActivity
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.loadUserAvatar
import com.music.player.ui.util.resolveThemeColorStateList
import com.music.player.ui.util.showAvatarPlaceholder
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.LibraryViewModel
import android.widget.Toast
import java.text.NumberFormat

class ProfileFragment : Fragment(), RootTabInteraction {

    private var _binding: FragmentProfileBinding? = null
    private val binding: FragmentProfileBinding
        get() = _binding!!

    private lateinit var authViewModel: AuthViewModel
    private lateinit var libraryViewModel: LibraryViewModel
    private var currentUser: UserProfile? = null
    private val avatarPicker =
        registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            uri ?: return@registerForActivityResult
            authViewModel.uploadAvatar(uri)
        }

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
        binding.stickyProfileTitle.applyStatusBarInsetPadding()
        binding.scrollContent.setOnScrollChangeListener { _, scrollY, _, _, _ ->
            binding.stickyProfileTitle.visibility = if (scrollY > 0) View.VISIBLE else View.GONE
        }
        setupUi()
        setupObservers()
        warmProfileData()
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

    private fun warmProfileData() {
        if (authViewModel.currentUser.value == null) {
            authViewModel.refreshProfile()
        }
        libraryViewModel.prefetch()
    }

    private fun refresh(userInitiated: Boolean) {
        if (!userInitiated) {
            warmProfileData()
            return
        }

        authViewModel.refreshProfile()
        libraryViewModel.refreshFavorites(silent = true, forceRefresh = true)
        libraryViewModel.refreshHistory(silent = true, forceRefresh = true)
        libraryViewModel.refreshPlaylists(silent = true, forceRefresh = true)
    }

    private fun setupUi() {
        binding.ivAvatar.setOnClickListener {
            avatarPicker.launch("image/*")
        }
        val openSettings = View.OnClickListener {
            settingsLauncher.launch(Intent(requireContext(), SettingsActivity::class.java))
        }
        binding.btnSettings.setOnClickListener(openSettings)
        binding.btnSettingsSticky.setOnClickListener(openSettings)
        val openLiked = View.OnClickListener { openCollection(SongCollectionFragment.newLiked()) }
        val openHistory = View.OnClickListener { openCollection(SongCollectionFragment.newHistory()) }
        binding.rowLiked.setOnClickListener(openLiked)
        binding.tvLikedTitle.setOnClickListener(openLiked)
        binding.rowHistory.setOnClickListener(openHistory)
        binding.tvHistoryTitle.setOnClickListener(openHistory)
        val openPlaylists = View.OnClickListener { openCollection(UserPlaylistsFragment()) }
        binding.rowPlaylists.setOnClickListener(openPlaylists)
        binding.tvPlaylistsTitle.setOnClickListener(openPlaylists)
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

        authViewModel.authState.observe(viewLifecycleOwner) { state ->
            when (state) {
                is AuthState.Loading -> setProfileActionsEnabled(false)
                is AuthState.Success -> {
                    setProfileActionsEnabled(true)
                    Toast.makeText(requireContext(), state.message, Toast.LENGTH_SHORT).show()
                    authViewModel.resetAuthState()
                }
                is AuthState.Error -> {
                    setProfileActionsEnabled(true)
                    Toast.makeText(requireContext(), state.message, Toast.LENGTH_LONG).show()
                    authViewModel.resetAuthState()
                }
                is AuthState.Idle -> setProfileActionsEnabled(true)
            }
        }

        libraryViewModel.favorites.observe(viewLifecycleOwner) { songs ->
            updateLikedSection(songs)
        }

        libraryViewModel.history.observe(viewLifecycleOwner) { songs ->
            updateHistorySection(songs)
        }

        libraryViewModel.playlists.observe(viewLifecycleOwner) { playlists ->
            updatePlaylistsSection(playlists)
        }
    }

    private fun updateLikedSection(songs: List<Song>) {
        binding.tvLikedCount.text = NumberFormat.getIntegerInstance().format(songs.size)
        updateLikedCover(songs.firstOrNull()?.album?.picUrl)
        binding.tvLikedMeta.text = if (songs.isEmpty()) {
            getString(R.string.profile_liked_empty)
        } else {
            getString(R.string.profile_liked_meta, songs.size, describeSong(songs.first()))
        }
    }

    private fun updateHistorySection(songs: List<Song>) {
        binding.tvHistoryCount.text = NumberFormat.getIntegerInstance().format(songs.size)
        updateHistoryCover(songs.firstOrNull()?.album?.picUrl)
        binding.tvHistoryMeta.text = if (songs.isEmpty()) {
            getString(R.string.profile_history_empty)
        } else {
            getString(R.string.profile_history_meta, songs.size, describeSong(songs.first()))
        }
    }

    private fun updatePlaylistsSection(playlists: List<UserPlaylist>) {
        binding.tvPlaylistCount.text = NumberFormat.getIntegerInstance().format(playlists.size)
        updatePlaylistCover(playlists.firstOrNull()?.coverUrl)
        binding.tvPlaylistsMeta.text = if (playlists.isEmpty()) {
            getString(R.string.user_playlist_empty)
        } else {
            val first = playlists.first().name
            getString(R.string.user_playlist_loaded_count, playlists.size, first)
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
            binding.ivLikedCover.setPadding(coverPlaceholderPadding())
            binding.ivLikedCover.scaleType = ImageView.ScaleType.CENTER
            binding.ivLikedCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivLikedCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
        } else {
            binding.ivLikedCover.setPadding(0, 0, 0, 0)
            binding.ivLikedCover.scaleType = ImageView.ScaleType.CENTER_CROP
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
            binding.ivHistoryCover.setPadding(coverPlaceholderPadding())
            binding.ivHistoryCover.scaleType = ImageView.ScaleType.CENTER
            binding.ivHistoryCover.setImageResource(R.drawable.ic_music_note_24)
            binding.ivHistoryCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
        } else {
            binding.ivHistoryCover.setPadding(0, 0, 0, 0)
            binding.ivHistoryCover.scaleType = ImageView.ScaleType.CENTER_CROP
            binding.ivHistoryCover.imageTintList = null
            Glide.with(binding.ivHistoryCover)
                .load(url)
                .placeholder(R.drawable.ic_music_note_24)
                .centerCrop()
                .into(binding.ivHistoryCover)
        }
    }

    private fun updatePlaylistCover(coverUrl: String?) {
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            binding.ivPlaylistCover.setPadding(coverPlaceholderPadding())
            binding.ivPlaylistCover.setImageResource(R.drawable.ic_playlist_24)
            binding.ivPlaylistCover.imageTintList = requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
            binding.ivPlaylistCover.scaleType = ImageView.ScaleType.CENTER
            return
        }

        binding.ivPlaylistCover.setPadding(0, 0, 0, 0)
        binding.ivPlaylistCover.imageTintList = null
        binding.ivPlaylistCover.scaleType = ImageView.ScaleType.CENTER_CROP
        Glide.with(binding.ivPlaylistCover)
            .load(url)
            .placeholder(R.drawable.ic_playlist_24)
            .centerCrop()
            .into(binding.ivPlaylistCover)
    }

    private fun ImageView.setPadding(padding: Int) {
        setPadding(padding, padding, padding, padding)
    }

    private fun coverPlaceholderPadding(): Int =
        resources.getDimensionPixelSize(R.dimen.profile_cover_placeholder_padding)

    private fun renderUser(user: UserProfile?) {
        if (user == null) {
            binding.tvNickname.text = getString(R.string.profile_nickname_placeholder)
            binding.tvSignature.text = getString(R.string.profile_signature_empty)
            binding.tvProfileMeta.text = getString(R.string.profile_account_placeholder)
            binding.tvBadge.visibility = View.GONE
            binding.ivAvatar.showAvatarPlaceholder(18)
            return
        }
        binding.tvNickname.text = user.nickname?.takeIf { it.isNotBlank() }
            ?: user.username?.takeIf { it.isNotBlank() }
            ?: user.email?.substringBefore("@")
            ?: getString(R.string.profile_nickname_placeholder)
        binding.tvSignature.text = user.signature?.takeIf { it.isNotBlank() }
            ?: getString(R.string.profile_signature_empty)
        binding.tvProfileMeta.text = buildProfileMeta(user)
        binding.ivAvatar.loadUserAvatar(user, placeholderPaddingDp = 18)

        if (!user.badge.isNullOrEmpty()) {
            binding.tvBadge.text = getString(R.string.profile_badge, user.badge)
            binding.tvBadge.visibility = View.VISIBLE
        } else {
            binding.tvBadge.visibility = View.GONE
        }
    }

    private fun setProfileActionsEnabled(enabled: Boolean) {
        binding.ivAvatar.isEnabled = enabled
        binding.ivAvatar.alpha = if (enabled) 1f else 0.6f
    }

    private fun buildProfileMeta(user: UserProfile): String {
        val primary = user.email?.trim().orEmpty()
            .ifBlank { user.username?.trim().orEmpty() }
            .ifBlank { user.nickname?.trim().orEmpty() }
            .ifBlank { getString(R.string.profile_account_placeholder) }

        val shortId = user.id.takeLast(6).uppercase()
        return getString(R.string.profile_account_meta, primary, shortId)
    }

}
