package com.music.player.ui.util

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.music.player.R
import com.music.player.data.auth.SupabaseClient
import com.music.player.data.auth.UserProfile
import java.io.File
import java.util.Locale
import kotlin.math.abs

/**
 * Resolve a loadable avatar model for Glide:
 * - remote http(s) URL (upgraded to https when needed)
 * - website relative paths such as `/api/v1/user/avatar/…` (joined to API base)
 * - local file path / file:// URI saved by avatar picker
 * - null when we should draw a local initials tile instead
 */
fun UserProfile.resolveAvatarModel(): Any? {
    val raw = avatar_url?.trim().orEmpty()
    if (raw.isBlank()) return null

    // Local file saved by UserProfilePreferences
    if (raw.startsWith("file:", ignoreCase = true)) {
        val path = runCatching { Uri.parse(raw).path }.getOrNull().orEmpty()
        if (path.isNotBlank()) {
            val file = File(path)
            if (file.isFile) return file
        }
        return Uri.parse(raw)
    }
    if (raw.startsWith("content:", ignoreCase = true)) {
        return Uri.parse(raw)
    }

    // Absolute remote URL
    if (raw.startsWith("http://", ignoreCase = true) ||
        raw.startsWith("https://", ignoreCase = true)
    ) {
        return ImageUrl.bestQuality(raw) ?: raw
    }

    // Absolute local filesystem path from avatar picker (e.g. /data/user/0/.../x.img).
    // Do NOT treat website paths like /api/v1/user/avatar/... as files.
    if (raw.startsWith("/") && looksLikeLocalFilesystemPath(raw)) {
        val file = File(raw)
        if (file.isFile) return file
        // Stale local path after reinstall — fall through to remote if it also looks web-like.
    } else if (raw.startsWith("/") && File(raw).isFile) {
        return File(raw)
    }

    // Relative site path: "/api/v1/user/avatar/2-xxx.png"
    absoluteApiUrl(raw)?.let { return ImageUrl.bestQuality(it) ?: it }

    return ImageUrl.bestQuality(raw) ?: raw
}

/**
 * Join a path-only avatar field to the auth/API origin.
 * Backend `/api/user/me` returns avatarUrl like `/api/v1/user/avatar/{id}.png`.
 */
fun absoluteApiUrl(pathOrUrl: String?): String? {
    val raw = pathOrUrl?.trim().orEmpty()
    if (raw.isBlank()) return null
    if (raw.startsWith("http://", ignoreCase = true) ||
        raw.startsWith("https://", ignoreCase = true)
    ) {
        return raw
    }
    if (raw.startsWith("file:", ignoreCase = true) ||
        raw.startsWith("content:", ignoreCase = true) ||
        looksLikeLocalFilesystemPath(raw)
    ) {
        return null
    }
    val base = SupabaseClient.SUPABASE_URL.trimEnd('/')
    if (base.isBlank()) return null
    return if (raw.startsWith("/")) "$base$raw" else "$base/$raw"
}

private fun looksLikeLocalFilesystemPath(path: String): Boolean {
    val lower = path.lowercase(Locale.US)
    return lower.startsWith("/data/") ||
        lower.startsWith("/storage/") ||
        lower.startsWith("/sdcard/") ||
        lower.startsWith("/mnt/") ||
        lower.startsWith("/android_asset/") ||
        // Avatar picker stores absolute paths under app filesDir
        lower.contains("/files/profile_avatars/")
}

/** @deprecated Prefer [resolveAvatarModel] + [ImageView.loadUserAvatar]. Kept for URL fields. */
fun UserProfile.resolveAvatarUrl(): String {
    val model = resolveAvatarModel()
    return when (model) {
        is String -> model
        is File -> model.toURI().toString()
        is Uri -> model.toString()
        else -> ""
    }
}

fun ImageView.loadUserAvatar(user: UserProfile?, placeholderPaddingDp: Int = 14) {
    if (user == null) {
        showAvatarPlaceholder(placeholderPaddingDp)
        return
    }

    // Critical: XML app:tint tints Glide bitmaps into a solid brand color (looks "empty").
    clearColorFilter()
    imageTintList = null
    setPadding(0, 0, 0, 0)
    scaleType = ImageView.ScaleType.CENTER_CROP

    val model = user.resolveAvatarModel()
    val fallback = user.createInitialsDrawable(
        context = context,
        widthPx = width.coerceAtLeast(128),
        heightPx = height.coerceAtLeast(128)
    )

    if (model == null) {
        setImageDrawable(fallback)
        return
    }

    Glide.with(this)
        .load(model)
        .circleCrop()
        .placeholder(fallback)
        .error(fallback)
        .into(this)
}

fun ImageView.showAvatarPlaceholder(paddingDp: Int = 14) {
    Glide.with(this).clear(this)
    val density = resources.displayMetrics.density
    val padding = (paddingDp * density).toInt()
    setPadding(padding, padding, padding, padding)
    scaleType = ImageView.ScaleType.CENTER
    setImageResource(R.drawable.ic_person_24)
    imageTintList = context.resolveThemeColorStateList(R.attr.brandPrimary)
}

fun UserProfile.createInitialsDrawable(
    context: Context,
    widthPx: Int,
    heightPx: Int
): Drawable {
    val size = maxOf(widthPx, heightPx, 128)
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    val seed = (nickname ?: username ?: email ?: id).trim().ifBlank { id }
    val bg = initialsBackgroundColor(seed)
    canvas.drawColor(bg)

    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textSize = size * 0.38f
    }
    val initials = seed.toInitials()
    val y = size / 2f - (paint.descent() + paint.ascent()) / 2f
    canvas.drawText(initials, size / 2f, y, paint)

    return BitmapDrawable(context.resources, bitmap)
}

private fun String.toInitials(): String {
    val cleaned = trim()
    if (cleaned.isEmpty()) return "?"
    val parts = cleaned.split(Regex("\\s+")).filter { it.isNotBlank() }
    return if (parts.size >= 2) {
        buildString {
            append(parts[0].first().uppercaseChar())
            append(parts[1].first().uppercaseChar())
        }
    } else {
        cleaned.take(2).uppercase(Locale.getDefault())
    }
}

private fun initialsBackgroundColor(seed: String): Int {
    // Stable pleasant hues from seed (no network).
    val palette = intArrayOf(
        0xFF5B8DEF.toInt(),
        0xFF7C5CBF.toInt(),
        0xFF2F9E8F.toInt(),
        0xFFE07A3D.toInt(),
        0xFFD94F70.toInt(),
        0xFF3D8BDB.toInt(),
        0xFF6B8E23.toInt(),
        0xFF9B59B6.toInt()
    )
    return palette[abs(seed.hashCode()) % palette.size]
}
