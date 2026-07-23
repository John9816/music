package com.music.player.ui.fragment

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.auth.UserProfile
import com.music.player.data.model.Song
import com.music.player.data.model.UserPlaylist
import com.music.player.databinding.FragmentProfileBinding
import com.music.player.databinding.ItemProfileBodyBinding
import com.music.player.ui.activity.DownloadsActivity
import com.music.player.ui.activity.SettingsActivity
import com.music.player.ui.util.FileSizeFormatter
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.SongDownloader
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.util.loadUserAvatar
import com.music.player.ui.util.resolveThemeColorStateList
import com.music.player.ui.util.showAvatarPlaceholder
import com.music.player.ui.viewmodel.AuthState
import com.music.player.ui.viewmodel.AuthViewModel
import com.music.player.ui.viewmodel.LibraryViewModel
import java.text.NumberFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Profile tab: fixed top bar + RecyclerView body (same scroll model as search / radio).
 */
class ProfileFragment : Fragment(), RootTabInteraction {

    private var _binding: FragmentProfileBinding? = null
    private val binding: FragmentProfileBinding
        get() = _binding!!

    private var _body: ItemProfileBodyBinding? = null
    private val body: ItemProfileBodyBinding
        get() = _body!!

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
        setupRecycler()
        setupHeroUi()
        setupObservers()
        warmProfileData()
        refreshDownloadsMeta()
    }

    override fun onResume() {
        super.onResume()
        refreshDownloadsMeta()
    }

    override fun onDestroyView() {
        binding.recyclerView.adapter = null
        _body = null
        super.onDestroyView()
        _binding = null
    }

    override fun onTabReselected() {
        val binding = _binding ?: return
        val lm = binding.recyclerView.layoutManager as? LinearLayoutManager
        val offset = lm?.findFirstVisibleItemPosition() ?: 0
        val top = lm?.findViewByPosition(offset)?.top ?: 0
        if (offset > 0 || top < 0) {
            binding.recyclerView.smoothScrollToPosition(0)
            return
        }
        refresh(userInitiated = true)
    }

    private fun setupRecycler() {
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.overScrollMode = View.OVER_SCROLL_NEVER
        binding.recyclerView.setHasFixedSize(true)
        binding.recyclerView.adapter = object : RecyclerView.Adapter<ProfileBodyHolder>() {
            override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ProfileBodyHolder {
                val bodyBinding = ItemProfileBodyBinding.inflate(
                    LayoutInflater.from(parent.context),
                    parent,
                    false
                )
                _body = bodyBinding
                setupBodyUi(bodyBinding)
                // Re-apply latest observed state after rebind (e.g. config change).
                renderUser(currentUser)
                libraryViewModel.favorites.value?.let { updateLikedSection(it) }
                libraryViewModel.history.value?.let { updateHistorySection(it) }
                libraryViewModel.playlists.value?.let { updatePlaylistsSection(it) }
                refreshDownloadsMeta()
                return ProfileBodyHolder(bodyBinding)
            }

            override fun onBindViewHolder(holder: ProfileBodyHolder, position: Int) = Unit

            override fun getItemCount(): Int = 1
        }
    }

    private fun setupHeroUi() {
        binding.btnSettings.bindPressFeedback(PressFeedback.Style.ICON)
        binding.btnSettings.setOnClickListener {
            settingsLauncher.launch(Intent(requireContext(), SettingsActivity::class.java))
        }
    }

    private fun setupBodyUi(body: ItemProfileBodyBinding) {
        body.ivAvatar.bindPressFeedback(PressFeedback.Style.ICON)
        body.layoutUserHeader.bindPressFeedback(PressFeedback.Style.ROW)
        body.cardLiked.bindPressFeedback(PressFeedback.Style.CARD)
        listOf(
            body.rowLiked,
            body.rowHistory,
            body.rowDownloads,
            body.rowPlaylists,
            body.gridLiked,
            body.gridHistory,
            body.gridDownloads,
            body.gridPlaylists
        ).forEach { it.bindPressFeedback(PressFeedback.Style.ROW) }

        body.ivAvatar.setOnClickListener {
            avatarPicker.launch("image/*")
        }
        body.layoutUserHeader.setOnClickListener {
            settingsLauncher.launch(Intent(requireContext(), SettingsActivity::class.java))
        }

        val openLiked = View.OnClickListener { openCollection(SongCollectionFragment.newLiked()) }
        val openHistory = View.OnClickListener { openCollection(SongCollectionFragment.newHistory()) }
        val openDownloads = View.OnClickListener {
            startActivity(Intent(requireContext(), DownloadsActivity::class.java))
        }
        val openPlaylists = View.OnClickListener { openCollection(UserPlaylistsFragment()) }

        body.cardLiked.setOnClickListener(openLiked)
        body.tvLikedTitle.setOnClickListener(openLiked)
        body.gridLiked.setOnClickListener(openLiked)
        body.rowLiked.setOnClickListener(openLiked)

        body.gridHistory.setOnClickListener(openHistory)
        body.rowHistory.setOnClickListener(openHistory)
        body.tvHistoryTitle.setOnClickListener(openHistory)

        body.gridDownloads.setOnClickListener(openDownloads)
        body.rowDownloads.setOnClickListener(openDownloads)
        body.tvDownloadsTitle.setOnClickListener(openDownloads)

        body.gridPlaylists.setOnClickListener(openPlaylists)
        body.rowPlaylists.setOnClickListener(openPlaylists)
        body.tvPlaylistsTitle.setOnClickListener(openPlaylists)
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
        libraryViewModel.prefetch(forceRefresh = userInitiated)
        refreshDownloadsMeta()
    }

    private fun refreshDownloadsMeta() {
        if (_body == null || _binding == null) return
        viewLifecycleOwner.lifecycleScope.launch {
            val summary = withContext(Dispatchers.IO) {
                // One song writes audio + sidecar .json/.cover; only count real audio files.
                val files = SongDownloader.downloadDirs(requireContext())
                    .flatMap { it.listFiles().orEmpty().asIterable() }
                    .filter { file ->
                        file.isFile &&
                            !file.name.endsWith(".part", ignoreCase = true) &&
                            file.extension.lowercase() in DOWNLOAD_AUDIO_EXTENSIONS
                    }
                    .distinctBy { it.absolutePath }
                val count = files.size
                val totalSize = files.sumOf { it.length().coerceAtLeast(0L) }
                count to totalSize
            }
            val body = _body ?: return@launch
            val (count, totalSize) = summary
            body.tvGridDownloadsCount.text = NumberFormat.getIntegerInstance().format(count)
            body.tvDownloadsMeta.text = if (count == 0) {
                getString(R.string.profile_downloads_empty)
            } else {
                getString(
                    R.string.profile_downloads_meta,
                    count,
                    FileSizeFormatter.format(totalSize)
                )
            }
        }
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
            if (_body != null) renderUser(user)
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
            if (_body != null) updateLikedSection(songs)
        }

        libraryViewModel.history.observe(viewLifecycleOwner) { songs ->
            if (_body != null) updateHistorySection(songs)
        }

        libraryViewModel.playlists.observe(viewLifecycleOwner) { playlists ->
            if (_body != null) updatePlaylistsSection(playlists)
        }
    }

    private fun updateLikedSection(songs: List<Song>) {
        val body = _body ?: return
        val countText = NumberFormat.getIntegerInstance().format(songs.size)
        body.tvLikedCount.text = countText
        body.tvGridLikedCount.text = countText
        updateLikedCover(songs.firstOrNull()?.album?.picUrl)
        body.tvLikedMeta.text = if (songs.isEmpty()) {
            getString(R.string.profile_liked_empty)
        } else {
            getString(R.string.profile_liked_card_subtitle, songs.size)
        }
    }

    private fun updateHistorySection(songs: List<Song>) {
        val body = _body ?: return
        val countText = NumberFormat.getIntegerInstance().format(songs.size)
        body.tvHistoryCount.text = countText
        body.tvGridHistoryCount.text = countText
        updateHistoryCover(songs.firstOrNull()?.album?.picUrl)
        body.tvHistoryMeta.text = if (songs.isEmpty()) {
            getString(R.string.profile_history_empty)
        } else {
            getString(R.string.profile_history_meta, songs.size, describeSong(songs.first()))
        }
    }

    private fun updatePlaylistsSection(playlists: List<UserPlaylist>) {
        val body = _body ?: return
        val countText = NumberFormat.getIntegerInstance().format(playlists.size)
        body.tvPlaylistCount.text = countText
        body.tvGridPlaylistsCount.text = countText
        updatePlaylistCover(playlists.firstOrNull()?.coverUrl)
        body.tvPlaylistsMeta.text = if (playlists.isEmpty()) {
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
        val body = _body ?: return
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            body.ivLikedCover.setPadding(coverPlaceholderPadding())
            body.ivLikedCover.scaleType = ImageView.ScaleType.CENTER
            body.ivLikedCover.setImageResource(R.drawable.ic_favorite_24)
            body.ivLikedCover.imageTintList =
                android.content.res.ColorStateList.valueOf(Color.WHITE)
        } else {
            body.ivLikedCover.setPadding(0, 0, 0, 0)
            body.ivLikedCover.scaleType = ImageView.ScaleType.CENTER_CROP
            body.ivLikedCover.imageTintList = null
            Glide.with(body.ivLikedCover)
                .load(url)
                .placeholder(R.drawable.ic_favorite_24)
                .centerCrop()
                .into(body.ivLikedCover)
        }
    }

    private fun updateHistoryCover(coverUrl: String?) {
        val body = _body ?: return
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            body.ivHistoryCover.setPadding(coverPlaceholderPadding())
            body.ivHistoryCover.scaleType = ImageView.ScaleType.CENTER
            body.ivHistoryCover.setImageResource(R.drawable.ic_music_note_24)
            body.ivHistoryCover.imageTintList =
                requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
        } else {
            body.ivHistoryCover.setPadding(0, 0, 0, 0)
            body.ivHistoryCover.scaleType = ImageView.ScaleType.CENTER_CROP
            body.ivHistoryCover.imageTintList = null
            Glide.with(body.ivHistoryCover)
                .load(url)
                .placeholder(R.drawable.ic_music_note_24)
                .centerCrop()
                .into(body.ivHistoryCover)
        }
    }

    private fun updatePlaylistCover(coverUrl: String?) {
        val body = _body ?: return
        val url = coverUrl?.trim().orEmpty()
        if (url.isBlank()) {
            body.ivPlaylistCover.setPadding(coverPlaceholderPadding())
            body.ivPlaylistCover.setImageResource(R.drawable.ic_playlist_24)
            body.ivPlaylistCover.imageTintList =
                requireContext().resolveThemeColorStateList(R.attr.brandPrimary)
            body.ivPlaylistCover.scaleType = ImageView.ScaleType.CENTER
            return
        }

        body.ivPlaylistCover.setPadding(0, 0, 0, 0)
        body.ivPlaylistCover.imageTintList = null
        body.ivPlaylistCover.scaleType = ImageView.ScaleType.CENTER_CROP
        Glide.with(body.ivPlaylistCover)
            .load(url)
            .placeholder(R.drawable.ic_playlist_24)
            .centerCrop()
            .into(body.ivPlaylistCover)
    }

    private fun ImageView.setPadding(padding: Int) {
        setPadding(padding, padding, padding, padding)
    }

    private fun coverPlaceholderPadding(): Int =
        resources.getDimensionPixelSize(R.dimen.profile_cover_placeholder_padding)

    private fun renderUser(user: UserProfile?) {
        val body = _body ?: return
        if (user == null) {
            body.tvNickname.text = getString(R.string.profile_nickname_placeholder)
            body.tvSignature.text = getString(R.string.profile_signature_empty)
            body.tvProfileMeta.text = getString(R.string.profile_account_placeholder)
            body.tvBadge.visibility = View.GONE
            body.ivAvatar.showAvatarPlaceholder(18)
            return
        }
        body.tvNickname.text = user.nickname?.takeIf { it.isNotBlank() }
            ?: user.username?.takeIf { it.isNotBlank() }
            ?: user.email?.substringBefore("@")
            ?: getString(R.string.profile_nickname_placeholder)
        body.tvSignature.text = user.signature?.takeIf { it.isNotBlank() }
            ?: getString(R.string.profile_signature_empty)
        body.tvProfileMeta.text = buildProfileMeta(user)
        body.ivAvatar.loadUserAvatar(user, placeholderPaddingDp = 16)

        if (!user.badge.isNullOrEmpty()) {
            body.tvBadge.text = getString(R.string.profile_badge, user.badge)
            body.tvBadge.visibility = View.VISIBLE
        } else {
            body.tvBadge.visibility = View.GONE
        }
    }

    private fun setProfileActionsEnabled(enabled: Boolean) {
        val body = _body ?: return
        body.ivAvatar.isEnabled = enabled
        body.ivAvatar.alpha = if (enabled) 1f else 0.6f
    }

    private fun buildProfileMeta(user: UserProfile): String {
        val primary = user.email?.trim().orEmpty()
            .ifBlank { user.username?.trim().orEmpty() }
            .ifBlank { user.nickname?.trim().orEmpty() }
            .ifBlank { getString(R.string.profile_account_placeholder) }

        val shortId = user.id.takeLast(6).uppercase()
        return getString(R.string.profile_account_meta, primary, shortId)
    }

    private class ProfileBodyHolder(
        binding: ItemProfileBodyBinding
    ) : RecyclerView.ViewHolder(binding.root)

    private companion object {
        private val DOWNLOAD_AUDIO_EXTENSIONS = setOf("mp3", "flac", "aac", "m4a", "wav", "ogg")
    }
}
