package com.music.player.ui.activity

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.view.LayoutInflater
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.resource.drawable.DrawableTransitionOptions
import com.google.android.material.chip.Chip
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textfield.TextInputEditText
import com.music.player.R
import com.music.player.data.vod.TvVodApiClient
import com.music.player.data.vod.TvVodCategory
import com.music.player.data.vod.TvVodItem
import com.music.player.databinding.ActivityTvVodBinding
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyNavigationBarInsetPadding
import com.music.player.ui.util.applyStatusBarInsetPadding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class TvVodActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTvVodBinding
    private lateinit var adapter: VodGridAdapter

    private var sourceUrl: String = ""
    private var categories: List<TvVodCategory> = emptyList()
    private var selectedTypeId: String = ""
    private var vodItems: List<TvVodItem> = emptyList()
    private var searchMode = false
    private var loadJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityTvVodBinding.inflate(layoutInflater)
        setContentView(binding.root)

        sourceUrl = TvVodApiClient.SourceStore.get(this)

        val lightBars = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) !=
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(rootView = binding.root, lightSystemBars = lightBars)
        binding.toolbar.applyStatusBarInsetPadding()
        binding.recyclerView.applyNavigationBarInsetPadding()

        binding.toolbar.setNavigationOnClickListener { finish() }

        val spanCount = resources.getInteger(R.integer.vod_grid_span_count)
        binding.recyclerView.layoutManager = GridLayoutManager(this, spanCount)
        adapter = VodGridAdapter { item -> onItemClicked(item) }
        binding.recyclerView.adapter = adapter

        binding.etSearch.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                performSearch(binding.etSearch.text?.toString().orEmpty().trim())
                true
            } else false
        }
        binding.etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (s.isNullOrBlank() && searchMode) {
                    searchMode = false
                    loadHome()
                }
            }
        })

        binding.fabSource.setOnClickListener { showSourceDialog() }

        loadHome()
    }

    private fun loadHome() {
        showLoading(getString(R.string.tv_vod_loading))
        loadJob?.cancel()
        loadJob = scope.launch {
            val categoriesResult = withContext(Dispatchers.IO) {
                TvVodApiClient.fetchCategories(sourceUrl)
            }
            categoriesResult.onSuccess { cats ->
                categories = cats
                buildCategoryChips()
            }
            val listResult = withContext(Dispatchers.IO) {
                TvVodApiClient.fetchVodList(sourceUrl)
            }
            listResult.onSuccess { resp ->
                vodItems = resp.list ?: emptyList()
                adapter.submitList(vodItems)
                showContent()
            }.onFailure { error ->
                showError(error.message ?: getString(R.string.tv_vod_load_failed))
            }
        }
    }

    private fun loadCategory(typeId: String) {
        showLoading(getString(R.string.tv_vod_loading))
        loadJob?.cancel()
        loadJob = scope.launch {
            val result = withContext(Dispatchers.IO) {
                TvVodApiClient.fetchVodList(sourceUrl, typeId = typeId)
            }
            result.onSuccess { resp ->
                vodItems = resp.list ?: emptyList()
                adapter.submitList(vodItems)
                showContent()
            }.onFailure { error ->
                showError(error.message ?: getString(R.string.tv_vod_load_failed))
            }
        }
    }

    private fun performSearch(keyword: String) {
        if (keyword.isBlank()) return
        searchMode = true
        showLoading(getString(R.string.tv_vod_searching))
        loadJob?.cancel()
        loadJob = scope.launch {
            val result = withContext(Dispatchers.IO) {
                TvVodApiClient.searchVod(sourceUrl, keyword = keyword)
            }
            result.onSuccess { resp ->
                vodItems = resp.list ?: emptyList()
                adapter.submitList(vodItems)
                showContent()
            }.onFailure { error ->
                showError(error.message ?: getString(R.string.tv_vod_search_failed))
            }
        }
    }

    private fun buildCategoryChips() {
        binding.chipGroup.removeAllViews()
        // "全部" chip
        val allChip = Chip(this).apply {
            text = getString(R.string.tv_vod_all)
            isCheckable = true
            isChecked = selectedTypeId.isEmpty()
            setOnClickListener { selectCategory("") }
        }
        binding.chipGroup.addView(allChip)

        categories.forEach { cat ->
            val chip = Chip(this).apply {
                text = cat.typeName
                isCheckable = true
                isChecked = cat.typeId == selectedTypeId
                setOnClickListener { selectCategory(cat.typeId) }
            }
            binding.chipGroup.addView(chip)
        }
    }

    private fun selectCategory(typeId: String) {
        selectedTypeId = typeId
        searchMode = false
        binding.etSearch.setText("")
        loadCategory(typeId)
    }

    private fun onItemClicked(item: TvVodItem) {
        VodDetailDialog.show(this, sourceUrl, item) { detail ->
            if (detail != null) {
                val playUrls = detail.parsePlayUrls()
                if (playUrls.isNotEmpty()) {
                    val firstUrl = playUrls.values.first().firstOrNull()?.second
                    if (firstUrl != null) {
                        startPlayer(detail.vodName, firstUrl)
                    }
                }
            }
        }
    }

    private fun startPlayer(title: String, url: String) {
        startActivity(VideoParseActivity.intent(this, url = url))
    }

    private fun showSourceDialog() {
        val input = TextInputEditText(this).apply {
            setText(sourceUrl)
            hint = getString(R.string.tv_vod_source_hint)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.tv_vod_change_source)
            .setView(input)
            .setPositiveButton(R.string.tv_vod_confirm) { _, _ ->
                val newUrl = input.text?.toString()?.trim().orEmpty()
                if (newUrl.isNotBlank() && newUrl != sourceUrl) {
                    sourceUrl = newUrl
                    TvVodApiClient.SourceStore.set(this, sourceUrl)
                    loadHome()
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showLoading(message: String) {
        binding.loadingContainer.isVisible = true
        binding.emptyContainer.isVisible = false
        binding.recyclerView.isVisible = false
        binding.tvLoading.text = message
    }

    private fun showContent() {
        binding.loadingContainer.isVisible = false
        binding.emptyContainer.isVisible = false
        binding.recyclerView.isVisible = true
    }

    private fun showError(message: String) {
        binding.loadingContainer.isVisible = false
        binding.recyclerView.isVisible = false
        binding.emptyContainer.isVisible = true
        binding.tvEmpty.text = message
    }

    companion object {
        fun intent(context: Context): Intent = Intent(context, TvVodActivity::class.java)
    }
}

// ══════════════════════════════════════════════
// 影片网格适配器
// ══════════════════════════════════════════════

private class VodGridAdapter(
    private val onClick: (TvVodItem) -> Unit
) : RecyclerView.Adapter<VodGridAdapter.VodViewHolder>() {

    private var items: List<TvVodItem> = emptyList()

    fun submitList(list: List<TvVodItem>) {
        items = list
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VodViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_vod_movie, parent, false)
        return VodViewHolder(view)
    }

    override fun onBindViewHolder(holder: VodViewHolder, position: Int) {
        holder.bind(items[position], onClick)
    }

    override fun getItemCount(): Int = items.size

    class VodViewHolder(itemView: android.view.View) : RecyclerView.ViewHolder(itemView) {
        private val ivPoster = itemView.findViewById<android.widget.ImageView>(R.id.ivPoster)
        private val tvTitle = itemView.findViewById<android.widget.TextView>(R.id.tvTitle)
        private val tvRemarks = itemView.findViewById<android.widget.TextView>(R.id.tvRemarks)
        private val cardRoot = itemView.findViewById<com.google.android.material.card.MaterialCardView>(R.id.cardRoot)

        fun bind(item: TvVodItem, onClick: (TvVodItem) -> Unit) {
            tvTitle.text = item.vodName
            if (item.vodRemarks.isNotBlank()) {
                tvRemarks.isVisible = true
                tvRemarks.text = item.vodRemarks
            } else {
                tvRemarks.isVisible = false
            }

            val picUrl = item.vodPic.ifBlank { null }
            if (picUrl != null) {
                Glide.with(ivPoster.context)
                    .load(picUrl)
                    .centerCrop()
                    .transition(DrawableTransitionOptions.withCrossFade())
                    .into(ivPoster)
            } else {
                ivPoster.setImageResource(com.music.player.R.drawable.ic_music_note_24)
            }

            cardRoot.setOnClickListener { onClick(item) }
        }
    }
}

// ══════════════════════════════════════════════
// 影片详情对话框
// ══════════════════════════════════════════════

object VodDetailDialog {

    fun show(
        activity: AppCompatActivity,
        sourceUrl: String,
        item: TvVodItem,
        onResult: (TvVodItem?) -> Unit
    ) {
        val dialog = MaterialAlertDialogBuilder(activity)
            .setTitle(item.vodName)
            .setMessage(activity.getString(R.string.tv_vod_loading_detail))
            .setNegativeButton(android.R.string.cancel, null)
            .show()

        android.os.Handler(android.os.Looper.getMainLooper()).post {
            kotlinx.coroutines.MainScope().launch {
                val detail = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    TvVodApiClient.fetchVodDetail(sourceUrl, item.vodId)
                }
                detail.onSuccess { detailItem ->
                    dialog.dismiss()
                    if (detailItem != null) {
                        showEpisodePicker(activity, detailItem, onResult)
                    } else {
                        onResult(null)
                    }
                }.onFailure {
                    dialog.dismiss()
                    onResult(null)
                }
            }
        }
    }

    private fun showEpisodePicker(
        activity: AppCompatActivity,
        item: TvVodItem,
        onResult: (TvVodItem?) -> Unit
    ) {
        val playUrls = item.parsePlayUrls()
        if (playUrls.isEmpty()) {
            onResult(null)
            return
        }

        // 取第一个来源的剧集列表
        val firstSource = playUrls.entries.first()
        val episodes = firstSource.value
        val sourceName = firstSource.key

        val episodeNames = episodes.map { it.first }.toTypedArray()
        MaterialAlertDialogBuilder(activity)
            .setTitle("${item.vodName} · $sourceName")
            .setItems(episodeNames) { _, which ->
                val url = episodes[which].second
                onResult(item.copy(vodPlayUrl = url))
            }
            .setNegativeButton(android.R.string.cancel) { _, _ -> onResult(null) }
            .show()
    }
}
