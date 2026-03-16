package com.music.player.data.repository

import android.content.Context
import android.content.SharedPreferences
import com.music.player.data.auth.AppVersionRow
import com.music.player.data.auth.SupabaseClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class AppVersionInfo(
    val version: String,
    val buildNumber: Int,
    val downloadUrl: String?,
    val description: String?,
    val forceUpdate: Boolean,
    val minBuildNumber: Int
)

class AppVersionRepository(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("auth_prefs", Context.MODE_PRIVATE)
    private val restApi = SupabaseClient.restApi

    private fun getToken(): String? = prefs.getString("access_token", null)

    suspend fun getLatestVersion(): Result<AppVersionInfo?> = withContext(Dispatchers.IO) {
        runCatching {
            val token = getToken() ?: return@runCatching null
            val response = restApi.listAppVersions(token = "Bearer $token")
            if (!response.isSuccessful) throw IllegalStateException("获取版本信息失败")
            response.body()?.firstOrNull()?.toInfo()
        }
    }

    private fun AppVersionRow.toInfo(): AppVersionInfo {
        return AppVersionInfo(
            version = version,
            buildNumber = build_number,
            downloadUrl = download_url,
            description = description,
            forceUpdate = force_update == true,
            minBuildNumber = min_build_number ?: 0
        )
    }
}

