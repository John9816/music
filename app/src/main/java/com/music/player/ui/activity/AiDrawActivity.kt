package com.music.player.ui.activity

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.text.Editable
import android.text.TextWatcher
import android.util.Base64
import android.view.inputmethod.InputMethodManager
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.core.view.isVisible
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import com.google.android.material.chip.Chip
import com.music.player.R
import com.music.player.data.ai.AiDrawClient
import com.music.player.databinding.ActivityAiDrawBinding
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyNavigationBarInsetPadding
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.bindPressFeedback
import com.music.player.ui.viewmodel.LibraryViewModel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Standalone AI image studio (text / local reference images → generate → save / share).
 * Optional: [EXTRA_PLAYLIST_ID] to apply result as playlist cover.
 *
 * Does not use backend history — third-party generate + local/gallery save only.
 */
class AiDrawActivity : AppCompatActivity() {

    private lateinit var binding: ActivityAiDrawBinding
    private lateinit var libraryViewModel: LibraryViewModel
    private var generateJob: Job? = null
    private var resultBitmap: Bitmap? = null
    private var resultRemoteUrl: String? = null
    private var savedFile: File? = null
    private var isGenerating: Boolean = false

    private var refUri1: Uri? = null
    private var refUri2: Uri? = null
    private var intentRef1: String? = null

    private val playlistId: String?
        get() = intent.getStringExtra(EXTRA_PLAYLIST_ID)?.takeIf { it.isNotBlank() }

    private val playlistName: String?
        get() = intent.getStringExtra(EXTRA_PLAYLIST_NAME)?.takeIf { it.isNotBlank() }

    private val pickRef1 = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) setLocalRef(slot = 1, uri = uri)
    }

    private val pickRef2 = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) setLocalRef(slot = 2, uri = uri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityAiDrawBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val lightBars = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) !=
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(rootView = binding.root, lightSystemBars = lightBars)
        binding.toolbar.applyStatusBarInsetPadding()
        binding.scroll.applyNavigationBarInsetPadding()
        binding.bottomBar.applyNavigationBarInsetPadding()

        libraryViewModel = ViewModelProvider(this)[LibraryViewModel::class.java]

        binding.toolbar.setNavigationOnClickListener { finish() }
        applyIntentDefaults()
        setupPromptUi()
        setupStyleChips()
        setupActions()
        updatePromptCount()
        showEmptyState(true)
    }

    override fun onDestroy() {
        generateJob?.cancel()
        super.onDestroy()
    }

    private fun applyIntentDefaults() {
        val prompt = intent.getStringExtra(EXTRA_PROMPT)?.takeIf { it.isNotBlank() }
        intentRef1 = intent.getStringExtra(EXTRA_REF1)?.takeIf { it.isNotBlank() }
        when {
            prompt != null -> binding.etPrompt.setText(prompt)
            playlistName != null ->
                binding.etPrompt.setText(getString(R.string.ai_cover_default_prompt, playlistName))
            else -> binding.etPrompt.setText(getString(R.string.ai_draw_default_prompt))
        }

        intentRef1?.let { ref ->
            if (ref.startsWith("http", ignoreCase = true) ||
                ref.startsWith("file:", ignoreCase = true) ||
                ref.startsWith("content:", ignoreCase = true)
            ) {
                showRefPreview(slot = 1, model = ref)
            }
        }

        val forPlaylist = playlistId != null
        binding.btnApplyPlaylist.isVisible = forPlaylist
        if (forPlaylist) {
            binding.toolbar.subtitle =
                getString(R.string.ai_draw_for_playlist, playlistName ?: playlistId)
        }
    }

    private fun setupPromptUi() {
        binding.etPrompt.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) = updatePromptCount()
        })
        binding.tilPrompt.setEndIconOnClickListener {
            binding.etPrompt.text?.clear()
            updatePromptCount()
        }
    }

    private fun setupStyleChips() {
        val chips = listOf(
            binding.chipStyleMusic,
            binding.chipStyleNeon,
            binding.chipStyleAnime,
            binding.chipStyleOil,
            binding.chipStyleMinimal,
            binding.chipStyleCyber
        )
        chips.forEach { chip ->
            chip.setOnClickListener {
                if (isGenerating) return@setOnClickListener
                val promptText = resolveChipPrompt(chip)
                binding.etPrompt.setText(promptText)
                binding.etPrompt.setSelection(binding.etPrompt.text?.length ?: 0)
                updatePromptCount()
            }
        }
    }

    private fun resolveChipPrompt(chip: Chip): String {
        // Prefer string resource mapped by chip id for reliability.
        val resId = when (chip.id) {
            R.id.chipStyleMusic -> R.string.ai_draw_prompt_music
            R.id.chipStyleNeon -> R.string.ai_draw_prompt_neon
            R.id.chipStyleAnime -> R.string.ai_draw_prompt_anime
            R.id.chipStyleOil -> R.string.ai_draw_prompt_oil
            R.id.chipStyleMinimal -> R.string.ai_draw_prompt_minimal
            R.id.chipStyleCyber -> R.string.ai_draw_prompt_cyber
            else -> null
        }
        if (resId != null) return getString(resId)
        return (chip.tag as? String)?.takeIf { it.isNotBlank() } ?: chip.text.toString()
    }

    private fun updatePromptCount() {
        val n = binding.etPrompt.text?.length ?: 0
        binding.tvPromptCount.text = getString(R.string.ai_draw_prompt_counter, n)
    }

    private fun setupActions() {
        binding.cardRef1.bindPressFeedback(PressFeedback.Style.CARD)
        binding.cardRef2.bindPressFeedback(PressFeedback.Style.CARD)
        binding.cardRef1.setOnClickListener {
            if (!isGenerating) pickRef1.launch("image/*")
        }
        binding.cardRef2.setOnClickListener {
            if (!isGenerating) pickRef2.launch("image/*")
        }
        binding.btnClearRef1.setOnClickListener { if (!isGenerating) clearRef(1) }
        binding.btnClearRef2.setOnClickListener { if (!isGenerating) clearRef(2) }

        binding.btnGenerate.setOnClickListener {
            if (isGenerating) return@setOnClickListener
            generate()
        }
        binding.btnCancel.setOnClickListener { cancelGenerate() }
        binding.btnSave.setOnClickListener { saveToGallery() }
        binding.btnShare.setOnClickListener { shareImage() }
        binding.btnApplyPlaylist.setOnClickListener { applyToPlaylist() }
    }

    private fun setLocalRef(slot: Int, uri: Uri) {
        if (slot == 1) {
            refUri1 = uri
            intentRef1 = null
        } else {
            refUri2 = uri
        }
        showRefPreview(slot, uri)
    }

    private fun clearRef(slot: Int) {
        if (slot == 1) {
            refUri1 = null
            intentRef1 = null
            binding.ivRef1.setImageDrawable(null)
            binding.ivRef1.isVisible = false
            binding.layoutRef1Empty.isVisible = true
            binding.btnClearRef1.isVisible = false
        } else {
            refUri2 = null
            binding.ivRef2.setImageDrawable(null)
            binding.ivRef2.isVisible = false
            binding.layoutRef2Empty.isVisible = true
            binding.btnClearRef2.isVisible = false
        }
    }

    private fun showRefPreview(slot: Int, model: Any) {
        val iv = if (slot == 1) binding.ivRef1 else binding.ivRef2
        val empty = if (slot == 1) binding.layoutRef1Empty else binding.layoutRef2Empty
        val clear = if (slot == 1) binding.btnClearRef1 else binding.btnClearRef2
        empty.isVisible = false
        iv.isVisible = true
        clear.isVisible = true
        Glide.with(this).load(model).centerCrop().into(iv)
    }

    private fun generate() {
        val prompt = binding.etPrompt.text?.toString()?.trim().orEmpty()
        if (prompt.isBlank()) {
            Toast.makeText(this, R.string.ai_cover_prompt_required, Toast.LENGTH_SHORT).show()
            binding.etPrompt.requestFocus()
            return
        }

        hideKeyboard()
        generateJob?.cancel()
        setLoading(true, getString(R.string.ai_draw_ref_encoding))
        // Keep previous result under the loading scrim (better than blank flash).
        setResultActionsEnabled(false)
        resultRemoteUrl = null
        savedFile = null

        generateJob = lifecycleScope.launch {
            try {
                val refs = withContext(Dispatchers.IO) {
                    val r1 = when {
                        refUri1 != null -> encodeUriToDataUri(refUri1!!)
                        !intentRef1.isNullOrBlank() -> intentRef1
                        else -> null
                    }
                    val r2 = refUri2?.let { encodeUriToDataUri(it) }
                    r1 to r2
                }
                if (isFinishing) return@launch

                val (ref1, ref2) = refs
                if (refUri1 != null && ref1 == null) {
                    failRefLoad()
                    return@launch
                }
                if (refUri2 != null && ref2 == null) {
                    failRefLoad()
                    return@launch
                }

                setLoading(true, getString(R.string.ai_draw_generating))
                val outcome = AiDrawClient.generate(prompt, ref1, ref2)
                if (isFinishing) return@launch

                outcome.onSuccess { image ->
                    resultRemoteUrl = image.imageUrl
                    when {
                        !image.imageUrl.isNullOrBlank() -> loadRemotePreview(image.imageUrl!!)
                        !image.imageBase64.isNullOrBlank() -> {
                            setLoading(false)
                            loadBase64Preview(image.imageBase64!!)
                            scrollToResult()
                        }
                        else -> {
                            setLoading(false)
                            binding.tvStatus.setText(R.string.ai_cover_failed)
                            Toast.makeText(this@AiDrawActivity, R.string.ai_cover_failed, Toast.LENGTH_SHORT).show()
                        }
                    }
                }.onFailure { e ->
                    if (e is CancellationException) return@onFailure
                    setLoading(false)
                    val msg = e.message ?: getString(R.string.ai_cover_failed)
                    binding.tvStatus.text = msg
                    Toast.makeText(this@AiDrawActivity, msg, Toast.LENGTH_SHORT).show()
                }
            } catch (ce: CancellationException) {
                setLoading(false)
                binding.tvStatus.setText(R.string.ai_draw_cancelled)
                throw ce
            } catch (t: Throwable) {
                setLoading(false)
                val msg = t.message ?: getString(R.string.ai_cover_failed)
                binding.tvStatus.text = msg
                Toast.makeText(this@AiDrawActivity, msg, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun failRefLoad() {
        setLoading(false)
        Toast.makeText(this, R.string.ai_draw_ref_load_failed, Toast.LENGTH_SHORT).show()
        binding.tvStatus.setText(R.string.ai_draw_ref_load_failed)
    }

    private fun cancelGenerate() {
        generateJob?.cancel()
        generateJob = null
        setLoading(false)
        binding.tvStatus.setText(R.string.ai_draw_cancelled)
        // Re-enable actions if we still have a previous bitmap under the scrim.
        setResultActionsEnabled(resultBitmap != null)
        if (resultBitmap == null) showEmptyState(true)
    }

    private fun encodeUriToDataUri(uri: Uri): String? {
        return runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            val w = bounds.outWidth.coerceAtLeast(1)
            val h = bounds.outHeight.coerceAtLeast(1)
            var sample = 1
            while (w / sample > MAX_REF_EDGE * 2 || h / sample > MAX_REF_EDGE * 2) {
                sample *= 2
            }
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val raw = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            } ?: error("decode null")

            val scaled = scaleDown(raw, MAX_REF_EDGE)
            if (scaled !== raw) raw.recycle()

            val baos = ByteArrayOutputStream()
            var quality = 85
            scaled.compress(Bitmap.CompressFormat.JPEG, quality, baos)
            while (baos.size() > MAX_REF_BYTES && quality > 50) {
                baos.reset()
                quality -= 10
                scaled.compress(Bitmap.CompressFormat.JPEG, quality, baos)
            }
            scaled.recycle()
            val b64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
            "data:image/jpeg;base64,$b64"
        }.onFailure {
            android.util.Log.w(TAG, "encodeUri failed for $uri", it)
        }.getOrNull()
    }

    private fun scaleDown(src: Bitmap, maxEdge: Int): Bitmap {
        val w = src.width
        val h = src.height
        val longest = maxOf(w, h)
        if (longest <= maxEdge) return src
        val scale = maxEdge.toFloat() / longest
        val nw = (w * scale).toInt().coerceAtLeast(1)
        val nh = (h * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, nw, nh, true)
    }

    private fun loadRemotePreview(url: String) {
        showEmptyState(false)
        Glide.with(this)
            .asBitmap()
            .load(url)
            .into(object : CustomTarget<Bitmap>() {
                override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                    if (isFinishing) return
                    resultBitmap = resource
                    binding.ivResult.clearColorFilter()
                    binding.ivResult.setImageBitmap(resource)
                    binding.ivResult.imageTintList = null
                    setLoading(false)
                    binding.tvStatus.setText(R.string.ai_draw_ready)
                    setResultActionsEnabled(true)
                    scrollToResult()
                }

                override fun onLoadCleared(placeholder: Drawable?) = Unit

                override fun onLoadFailed(errorDrawable: Drawable?) {
                    if (isFinishing) return
                    setLoading(false)
                    binding.tvStatus.setText(R.string.ai_draw_preview_load_failed)
                    // Remote URL still shareable via browser if needed; enable if URL exists.
                    setResultActionsEnabled(resultRemoteUrl != null && resultBitmap != null)
                    Toast.makeText(
                        this@AiDrawActivity,
                        R.string.ai_draw_preview_load_failed,
                        Toast.LENGTH_SHORT
                    ).show()
                }
            })
    }

    private fun loadBase64Preview(data: String) {
        showEmptyState(false)
        runCatching {
            val pure = data.substringAfter("base64,", data).replace("\\s".toRegex(), "")
            val bytes = Base64.decode(pure, Base64.DEFAULT)
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: error("decode failed")
            resultBitmap = bmp
            binding.ivResult.clearColorFilter()
            binding.ivResult.setImageBitmap(bmp)
            binding.ivResult.imageTintList = null
            binding.tvStatus.setText(R.string.ai_draw_ready)
            setResultActionsEnabled(true)
        }.onFailure {
            binding.tvStatus.setText(R.string.ai_draw_preview_load_failed)
            Toast.makeText(this, R.string.ai_draw_preview_load_failed, Toast.LENGTH_SHORT).show()
        }
    }

    private fun saveToGallery() {
        val bmp = resultBitmap
        if (bmp == null) {
            Toast.makeText(this, R.string.ai_draw_no_result, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val displayName = "DuckMusic_AI_${System.currentTimeMillis()}.jpg"
            val ok = withContext(Dispatchers.IO) {
                // Always keep app-private copy for share.
                savedFile = writeBitmapFile(bmp, displayName)
                saveBitmapToPublicGallery(bmp, displayName)
            }
            if (ok) {
                Toast.makeText(this@AiDrawActivity, R.string.ai_draw_saved_gallery, Toast.LENGTH_SHORT).show()
            } else {
                // Fallback: private file only
                val file = savedFile
                if (file != null) {
                    Toast.makeText(
                        this@AiDrawActivity,
                        getString(R.string.ai_draw_saved_path, file.name),
                        Toast.LENGTH_SHORT
                    ).show()
                } else {
                    Toast.makeText(this@AiDrawActivity, R.string.ai_draw_save_failed, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun saveBitmapToPublicGallery(bitmap: Bitmap, displayName: String): Boolean {
        return runCatching {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/DuckMusic")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val uri = contentResolver.insert(collection, values) ?: return@runCatching false
            contentResolver.openOutputStream(uri)?.use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)) {
                    return@runCatching false
                }
            } ?: return@runCatching false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            }
            true
        }.getOrDefault(false)
    }

    private fun shareImage() {
        lifecycleScope.launch {
            val file = savedFile ?: resultBitmap?.let { bmp ->
                withContext(Dispatchers.IO) { writeBitmapFile(bmp) }
            }
            if (file == null || !file.isFile) {
                Toast.makeText(this@AiDrawActivity, R.string.ai_draw_no_result, Toast.LENGTH_SHORT).show()
                return@launch
            }
            savedFile = file
            val uri = FileProvider.getUriForFile(
                this@AiDrawActivity,
                "${packageName}.fileprovider",
                file
            )
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "image/jpeg"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(share, getString(R.string.ai_draw_share)))
        }
    }

    private fun applyToPlaylist() {
        val id = playlistId ?: return
        val remote = resultRemoteUrl?.trim().orEmpty()
        lifecycleScope.launch {
            val cover = when {
                remote.isNotBlank() -> remote
                else -> {
                    val bmp = resultBitmap ?: run {
                        Toast.makeText(this@AiDrawActivity, R.string.ai_draw_no_result, Toast.LENGTH_SHORT).show()
                        return@launch
                    }
                    val file = withContext(Dispatchers.IO) { writeBitmapFile(bmp, "playlist_$id.jpg") }
                        ?: run {
                            Toast.makeText(this@AiDrawActivity, R.string.ai_draw_save_failed, Toast.LENGTH_SHORT).show()
                            return@launch
                        }
                    file.toURI().toString()
                }
            }
            libraryViewModel.updatePlaylistCover(id, cover)
            Toast.makeText(this@AiDrawActivity, R.string.ai_draw_applied_playlist, Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun writeBitmapFile(bitmap: Bitmap, name: String? = null): File? {
        return runCatching {
            val dir = File(filesDir, "ai_draw").apply { mkdirs() }
            val file = File(
                dir,
                name ?: "ai_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.jpg"
            )
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)
            }
            file
        }.getOrNull()
    }

    private fun setLoading(loading: Boolean, message: String? = null) {
        isGenerating = loading
        binding.layoutLoading.isVisible = loading
        if (loading && message != null) {
            binding.tvLoadingHint.text = message
            binding.tvStatus.text = message
        }
        binding.btnGenerate.isEnabled = !loading
        binding.btnGenerate.text = getString(
            if (loading) R.string.ai_draw_generating_btn else R.string.ai_draw_generate
        )
        binding.etPrompt.isEnabled = !loading
        binding.cardRef1.isClickable = !loading
        binding.cardRef2.isClickable = !loading
        binding.btnClearRef1.isEnabled = !loading
        binding.btnClearRef2.isEnabled = !loading
        for (i in 0 until binding.chipStyles.childCount) {
            binding.chipStyles.getChildAt(i)?.isEnabled = !loading
        }
        if (loading) {
            showEmptyState(false)
        }
    }

    private fun showEmptyState(empty: Boolean) {
        binding.layoutEmpty.isVisible = empty && !isGenerating
        if (empty) {
            binding.ivResult.setImageResource(R.drawable.ic_music_note_24)
        }
    }

    private fun setResultActionsEnabled(enabled: Boolean) {
        binding.btnSave.isEnabled = enabled
        binding.btnShare.isEnabled = enabled
        binding.btnApplyPlaylist.isEnabled = enabled && playlistId != null
    }

    private fun scrollToResult() {
        binding.scroll.post {
            val y = binding.cardResult.top - binding.scroll.paddingTop
            binding.scroll.smoothScrollTo(0, y.coerceAtLeast(0))
        }
    }

    private fun hideKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        val focus = currentFocus ?: binding.etPrompt
        imm?.hideSoftInputFromWindow(focus.windowToken, 0)
        binding.etPrompt.clearFocus()
    }

    companion object {
        private const val TAG = "AiDrawActivity"
        private const val MAX_REF_EDGE = 1024
        private const val MAX_REF_BYTES = 900_000

        const val EXTRA_PROMPT = "extra_prompt"
        const val EXTRA_REF1 = "extra_ref1"
        const val EXTRA_PLAYLIST_ID = "extra_playlist_id"
        const val EXTRA_PLAYLIST_NAME = "extra_playlist_name"

        fun intent(
            context: Context,
            prompt: String? = null,
            ref1: String? = null,
            playlistId: String? = null,
            playlistName: String? = null
        ): Intent = Intent(context, AiDrawActivity::class.java).apply {
            prompt?.let { putExtra(EXTRA_PROMPT, it) }
            ref1?.let { putExtra(EXTRA_REF1, it) }
            playlistId?.let { putExtra(EXTRA_PLAYLIST_ID, it) }
            playlistName?.let { putExtra(EXTRA_PLAYLIST_NAME, it) }
        }
    }
}
