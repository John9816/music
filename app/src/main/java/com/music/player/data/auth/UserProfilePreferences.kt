package com.music.player.data.auth

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

internal class UserProfilePreferences(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun applyTo(profile: UserProfile): UserProfile {
        val prefix = keyPrefix(profile.id)
        return profile.copy(
            username = valueIfStored(prefix + KEY_USERNAME) ?: profile.username,
            nickname = valueIfStored(prefix + KEY_NICKNAME) ?: profile.nickname,
            signature = valueIfStored(prefix + KEY_SIGNATURE) ?: profile.signature,
            avatar_url = valueIfStored(prefix + KEY_AVATAR) ?: profile.avatar_url
        )
    }

    fun save(
        profile: UserProfile,
        username: String?,
        nickname: String?,
        signature: String?,
        avatarUrl: String?
    ): UserProfile {
        val prefix = keyPrefix(profile.id)
        prefs.edit()
            .putString(prefix + KEY_USERNAME, username.orEmpty().trim())
            .putString(prefix + KEY_NICKNAME, nickname.orEmpty().trim())
            .putString(prefix + KEY_SIGNATURE, signature.orEmpty().trim())
            .putString(prefix + KEY_AVATAR, avatarUrl.orEmpty().trim())
            .apply()
        return applyTo(profile)
    }

    suspend fun saveAvatar(profile: UserProfile, source: Uri): UserProfile = withContext(Dispatchers.IO) {
        val mimeType = appContext.contentResolver.getType(source)
        require(mimeType == null || mimeType.startsWith("image/")) { "请选择有效的图片文件" }

        val directory = File(appContext.filesDir, "profile_avatars").apply { mkdirs() }
        val target = File(directory, "${safeFileName(profile.id)}.img")
        val temporary = File(directory, "${safeFileName(profile.id)}.tmp")
        val input = appContext.contentResolver.openInputStream(source)
            ?: throw IllegalArgumentException("无法读取所选图片")

        try {
            input.use { stream ->
                temporary.outputStream().buffered().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        total += read
                        require(total <= MAX_AVATAR_BYTES) { "头像文件不能超过 10 MB" }
                        output.write(buffer, 0, read)
                    }
                }
            }
            check(temporary.renameTo(target) || temporary.copyTo(target, overwrite = true).exists()) {
                "无法保存头像"
            }
        } finally {
            temporary.delete()
        }

        val prefix = keyPrefix(profile.id)
        // Absolute path is the most reliable Glide load model across Android versions.
        prefs.edit().putString(prefix + KEY_AVATAR, target.absolutePath).apply()
        applyTo(profile.copy(avatar_url = target.absolutePath))
    }

    private fun valueIfStored(key: String): String? {
        if (!prefs.contains(key)) return null
        return prefs.getString(key, null).orEmpty().takeIf { it.isNotBlank() }
    }

    private fun keyPrefix(userId: String): String = "${safeFileName(userId)}_"

    private fun safeFileName(value: String): String {
        return value.replace(Regex("[^A-Za-z0-9._-]"), "_").take(120)
    }

    private companion object {
        private const val PREFS_NAME = "local_user_profiles"
        private const val KEY_USERNAME = "username"
        private const val KEY_NICKNAME = "nickname"
        private const val KEY_SIGNATURE = "signature"
        private const val KEY_AVATAR = "avatar"
        private const val MAX_AVATAR_BYTES = 10L * 1024L * 1024L
    }
}
