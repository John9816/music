package com.music.player.data.repository

import android.content.Context
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.music.player.BuildConfig
import com.music.player.data.api.NetworkRuntime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

data class AppVersionInfo(
    val version: String,
    val buildNumber: Int,
    val downloadUrl: String?,
    val description: String?,
    val forceUpdate: Boolean,
    val minBuildNumber: Int
)

class AppVersionRepository(context: Context) {
    @Suppress("UNUSED_PARAMETER")
    private val appContext = context.applicationContext
    private val client = OkHttpClient.Builder()
        .connectionPool(NetworkRuntime.connectionPool())
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .build()

    suspend fun getLatestVersion(): Result<AppVersionInfo?> = withContext(Dispatchers.IO) {
        var lastError: Throwable? = null
        for (source in UPDATE_SOURCES) {
            val result = runCatching { fetchVersion(source) }
            val version = result.getOrNull()
            if (version != null) return@withContext Result.success(version)
            if (result.isFailure) lastError = result.exceptionOrNull()
        }
        if (lastError == null) Result.success(null) else Result.failure(lastError)
    }

    private fun fetchVersion(source: String): AppVersionInfo? {
        val request = Request.Builder()
            .url(source)
            .header("Accept", "application/json, application/vnd.github+json")
            .header("User-Agent", "Duck-Music-Android/${BuildConfig.VERSION_NAME}")
            .build()
        client.newCall(request).execute().use { response ->
            if (response.code == 404) return null
            if (!response.isSuccessful) throw IllegalStateException("检查更新失败 (HTTP ${response.code})")
            val root = JsonParser.parseString(response.body?.string().orEmpty()).asJsonObject
            return if (root.has("tag_name")) parseReleaseRoot(root) else parseUpdateManifest(root)
        }
    }

    private fun parseRelease(raw: String): AppVersionInfo? {
        return parseReleaseRoot(JsonParser.parseString(raw).asJsonObject)
    }

    private fun parseReleaseRoot(root: JsonObject): AppVersionInfo? {
        if (root.booleanOrFalse("draft") || root.booleanOrFalse("prerelease")) return null
        val version = root.stringOrNull("tag_name")?.removePrefix("v")?.removePrefix("V")
            ?: return null
        val assets = root.getAsJsonArray("assets")
            ?.mapNotNull { element -> element.takeIf { it.isJsonObject }?.asJsonObject }
            .orEmpty()
        val description = root.stringOrNull("body")

        return AppVersionInfo(
            version = version,
            buildNumber = runCatching { root.get("id")?.asInt }.getOrNull() ?: version.hashCode(),
            downloadUrl = selectCompatibleApk(assets, version)?.stringOrNull("browser_download_url"),
            description = description,
            forceUpdate = description?.contains("[force-update]", ignoreCase = true) == true,
            minBuildNumber = 0
        )
    }

    private fun parseUpdateManifest(root: JsonObject): AppVersionInfo? {
        val version = root.stringOrNull("version") ?: return null
        return AppVersionInfo(
            version = version.removePrefix("v").removePrefix("V"),
            buildNumber = root.intOrNull("buildNumber") ?: version.hashCode(),
            downloadUrl = root.stringOrNull("downloadUrl") ?: root.stringOrNull("download_url"),
            description = root.stringOrNull("description"),
            forceUpdate = root.booleanOrFalse("forceUpdate"),
            minBuildNumber = root.intOrNull("minBuildNumber") ?: 0
        )
    }

    private fun selectCompatibleApk(assets: List<JsonObject>, version: String): JsonObject? {
        val selectedName = ReleaseApkSelector.selectName(
            assetNames = assets.mapNotNull { it.stringOrNull("name") },
            version = version,
            debug = BuildConfig.DEBUG
        ) ?: return null
        return assets.firstOrNull {
            it.stringOrNull("name").equals(selectedName, ignoreCase = true)
        }
    }

    private fun JsonObject.stringOrNull(name: String): String? {
        val value = get(name) ?: return null
        if (value.isJsonNull || !value.isJsonPrimitive) return null
        return value.asString.trim().takeIf { it.isNotBlank() }
    }

    private fun JsonObject.booleanOrFalse(name: String): Boolean {
        return runCatching { get(name)?.asBoolean ?: false }.getOrDefault(false)
    }

    private fun JsonObject.intOrNull(name: String): Int? {
        return runCatching { get(name)?.takeUnless { it.isJsonNull }?.asInt }.getOrNull()
    }

    private companion object {
        private const val ECS_UPDATE_MANIFEST_URL =
            "https://api.751152.xyz/updates/latest.json"
        private const val LATEST_RELEASE_URL =
            "https://api.github.com/repos/John9816/music/releases/latest"
        private val UPDATE_SOURCES = listOf(ECS_UPDATE_MANIFEST_URL, LATEST_RELEASE_URL)
    }
}

internal object VersionComparator {
    fun isNewer(current: String, candidate: String): Boolean {
        val currentParts = numericParts(current)
        val candidateParts = numericParts(candidate)
        val length = maxOf(currentParts.size, candidateParts.size)
        for (index in 0 until length) {
            val currentPart = currentParts.getOrElse(index) { 0 }
            val candidatePart = candidateParts.getOrElse(index) { 0 }
            if (candidatePart != currentPart) return candidatePart > currentPart
        }
        return false
    }

    private fun numericParts(version: String): List<Int> {
        return version.trim().removePrefix("v").removePrefix("V")
            .substringBefore('-')
            .split('.')
            .map { part -> part.takeWhile(Char::isDigit).toIntOrNull() ?: 0 }
    }
}

internal object ReleaseApkSelector {
    fun selectName(assetNames: List<String>, version: String, debug: Boolean): String? {
        val normalizedVersion = version.trim().removePrefix("v").removePrefix("V")
        val expectedName = if (debug) {
            "DuckMusic-v$normalizedVersion-debug.apk"
        } else {
            "DuckMusic-v$normalizedVersion.apk"
        }
        return assetNames.firstOrNull { it.equals(expectedName, ignoreCase = true) }
    }
}
