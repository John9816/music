package com.music.player.data.video

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

/**
 * 聚合短视频解析：http://www.yx520.ltd/API/jhjx/api.php
 *
 * 参数：url（分享链接）、apikey
 * 成功/失败 JSON 形态不统一，[parseResponse] 兼容常见字段。
 */
object VideoParseClient {

    private const val ENDPOINT = "http://www.yx520.ltd/API/jhjx/api.php"

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .callTimeout(50, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    private val urlInText: Pattern = Pattern.compile(
        "https?://[^\\s\\u4e00-\\u9fff\"'<>]+",
        Pattern.CASE_INSENSITIVE
    )

    data class ParseResult(
        val title: String = "",
        val coverUrl: String? = null,
        val videoUrl: String? = null,
        val audioUrl: String? = null,
        val imageUrls: List<String> = emptyList(),
        val raw: String = ""
    ) {
        val hasMedia: Boolean
            get() = !videoUrl.isNullOrBlank() ||
                !audioUrl.isNullOrBlank() ||
                imageUrls.isNotEmpty()
    }

    /**
     * Pull first http(s) URL from share text (抖音等常夹带文案).
     */
    fun extractUrl(input: String): String {
        val trimmed = input.trim()
        if (trimmed.startsWith("http://", true) || trimmed.startsWith("https://", true)) {
            return trimmed.split(Regex("\\s+")).first()
        }
        val m = urlInText.matcher(trimmed)
        return if (m.find()) m.group().trimEnd('.', ',', ')', ']', '。', '，') else trimmed
    }

    suspend fun parse(shareText: String, apiKey: String): Result<ParseResult> =
        withContext(Dispatchers.IO) {
            runCatching {
                val key = apiKey.trim()
                require(key.isNotBlank()) { "请配置视频解析 apikey" }
                val link = extractUrl(shareText)
                require(link.isNotBlank()) { "请粘贴视频分享链接" }
                require(link.startsWith("http", ignoreCase = true)) {
                    "未识别到有效链接，请粘贴完整分享内容"
                }

                val httpUrl = ENDPOINT.toHttpUrl().newBuilder()
                    .addQueryParameter("url", link)
                    .addQueryParameter("apikey", key)
                    .build()

                val request = Request.Builder()
                    .url(httpUrl)
                    .get()
                    .header("Accept", "application/json, text/plain, */*")
                    .header("User-Agent", "MusicPlayer/1.0 (Android)")
                    .build()

                client.newCall(request).execute().use { response ->
                    val body = response.body?.string().orEmpty()
                    when (response.code) {
                        200 -> {
                            val parsed = parseResponse(body)
                            if (!parsed.hasMedia) {
                                // Some APIs return business error inside 200 body.
                                val err = extractErrorMessage(body)
                                error(err ?: "解析成功但未找到视频/图集直链")
                            }
                            parsed
                        }
                        403 -> error(extractErrorMessage(body) ?: "访问被拒绝（apikey 无效或权限不足）")
                        404 -> error("接口地址无效（404）")
                        429 -> error("请求过于频繁，请稍后再试")
                        500 -> error(extractErrorMessage(body) ?: "服务器内部错误")
                        else -> error(
                            extractErrorMessage(body)
                                ?: "解析失败 HTTP ${response.code}"
                        )
                    }
                }
            }
        }

    fun parseResponse(raw: String): ParseResult {
        val text = raw.trim()
        if (text.isBlank()) return ParseResult(raw = raw)

        // Plain URL body
        if (text.startsWith("http://", true) || text.startsWith("https://", true)) {
            val only = text.lineSequence().first().trim()
            return if (looksLikeMedia(only)) {
                ParseResult(videoUrl = only, raw = raw)
            } else {
                ParseResult(raw = raw)
            }
        }

        val root = runCatching { JSONObject(text) }.getOrNull()
            ?: return ParseResult(raw = raw)

        // Nested error object: {"error":{"code":403,"message":"..."}}
        root.optJSONObject("error")?.let { err ->
            val code = err.optInt("code", 0)
            if (code != 0 && code != 200) {
                return ParseResult(raw = raw)
            }
        }

        // Business code gate when present
        val code = firstInt(root, "code", "status", "code_num")
        if (code != null && code !in SUCCESS_CODES) {
            return ParseResult(raw = raw)
        }

        val data = when {
            root.optJSONObject("data") != null -> root.optJSONObject("data")!!
            root.optJSONObject("result") != null -> root.optJSONObject("result")!!
            root.optJSONObject("info") != null -> root.optJSONObject("info")!!
            else -> root
        }

        val title = firstString(
            data, root,
            "title", "desc", "name", "video_title", "content"
        ).orEmpty()

        val cover = firstString(
            data, root,
            "cover", "cover_url", "pic", "picurl", "img", "image", "poster", "thumbnail"
        )

        val video = firstMediaUrl(
            data, root,
            "url", "video", "video_url", "play", "play_url", "playurl",
            "downurl", "down_url", "videoUrl", "nwm_video_url", "wm_video_url",
            "video_addr", "mp4", "src"
        )

        val audio = firstMediaUrl(
            data, root,
            "music", "music_url", "audio", "audio_url", "bgm", "song"
        )

        val images = mutableListOf<String>()
        collectUrls(data.opt("images"), images)
        collectUrls(data.opt("pics"), images)
        collectUrls(data.opt("img_list"), images)
        collectUrls(data.opt("image_list"), images)
        collectUrls(root.opt("images"), images)
        if (images.isEmpty() && video == null) {
            firstString(data, root, "image", "img", "pic")?.let { images += it }
        }

        return ParseResult(
            title = title,
            coverUrl = cover,
            videoUrl = video,
            audioUrl = audio,
            imageUrls = images.distinct(),
            raw = raw
        )
    }

    fun extractErrorMessage(raw: String): String? {
        val text = raw.trim()
        if (text.isBlank()) return null
        val root = runCatching { JSONObject(text) }.getOrNull() ?: return null
        root.optJSONObject("error")?.let { err ->
            firstString(err, keys = arrayOf("message", "msg", "error", "info"))
                ?.takeIf { it.isNotBlank() }
                ?.let { return it }
        }
        return firstString(
            root,
            keys = arrayOf("message", "msg", "error", "info", "tip", "errmsg")
        )?.takeIf { it.isNotBlank() && !it.equals("success", true) && it != "ok" }
    }

    private val SUCCESS_CODES = setOf(0, 1, 200, 20000)

    private fun firstInt(obj: JSONObject, vararg keys: String): Int? {
        for (k in keys) {
            if (!obj.has(k) || obj.isNull(k)) continue
            val v = obj.opt(k) ?: continue
            when (v) {
                is Number -> return v.toInt()
                is String -> v.trim().toIntOrNull()?.let { return it }
            }
        }
        return null
    }

    private fun firstString(primary: JSONObject, fallback: JSONObject? = null, vararg keys: String): String? {
        firstString(primary, keys = keys)?.let { return it }
        if (fallback != null && fallback !== primary) {
            firstString(fallback, keys = keys)?.let { return it }
        }
        return null
    }

    private fun firstString(obj: JSONObject, vararg keys: String): String? {
        for (k in keys) {
            if (!obj.has(k) || obj.isNull(k)) continue
            val v = obj.opt(k) ?: continue
            when (v) {
                is String -> v.trim().takeIf { it.isNotBlank() }?.let { return it }
                is JSONArray -> {
                    if (v.length() > 0) {
                        v.optString(0).trim().takeIf { it.isNotBlank() }?.let { return it }
                    }
                }
                is JSONObject -> {
                    firstString(
                        v,
                        keys = arrayOf("url", "src", "href", "link", "download")
                    )?.let { return it }
                }
            }
        }
        return null
    }

    private fun firstMediaUrl(primary: JSONObject, fallback: JSONObject, vararg keys: String): String? {
        firstString(primary, keys = keys)?.takeIf { looksLikeMedia(it) || it.startsWith("http") }
            ?.let { return it }
        firstString(fallback, keys = keys)?.takeIf { looksLikeMedia(it) || it.startsWith("http") }
            ?.let { return it }
        return null
    }

    private fun collectUrls(node: Any?, out: MutableList<String>) {
        when (node) {
            null, JSONObject.NULL -> Unit
            is String -> node.trim().takeIf { it.startsWith("http") }?.let { out += it }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    collectUrls(node.opt(i), out)
                }
            }
            is JSONObject -> {
                firstString(
                    node,
                    keys = arrayOf("url", "src", "href", "link", "download", "pic", "image")
                )?.let { out += it }
            }
        }
    }

    private fun looksLikeMedia(url: String): Boolean {
        val u = url.lowercase()
        return u.startsWith("http") && (
            u.contains(".mp4") ||
                u.contains(".m3u8") ||
                u.contains(".flv") ||
                u.contains(".mov") ||
                u.contains(".webm") ||
                u.contains(".mp3") ||
                u.contains(".m4a") ||
                u.contains("video") ||
                u.contains("play") ||
                u.contains("cdn")
            )
    }
}
