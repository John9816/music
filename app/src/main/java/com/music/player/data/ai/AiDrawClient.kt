package com.music.player.data.ai

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

/**
 * Client for the third-party AI image API:
 * `https://ecyapi.cn/API/ai_draw_juhe.php`
 *
 * - message: prompt (required)
 * - url1 / url2: optional reference — http(s) URL **or** data-URI / base64
 *
 * Local picks are encoded as `data:image/jpeg;base64,...` and sent via **POST**
 * so large payloads are not stuffed into a GET query string.
 *
 * Response format is not strictly documented; [parseImageResult] accepts common shapes
 * (JSON url fields, plain URL, data-URI, HTML img src).
 */
object AiDrawClient {

    private const val TAG = "AiDrawClient"
    private const val ENDPOINT = "https://ecyapi.cn/API/ai_draw_juhe.php"

    /** Prefer POST when any ref looks like base64 / data-URI (query would be huge). */
    private const val POST_THRESHOLD_CHARS = 400

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .callTimeout(150, TimeUnit.SECONDS)
            .build()
    }

    data class Result(
        val imageUrl: String? = null,
        val imageBase64: String? = null,
        val raw: String = ""
    ) {
        val hasImage: Boolean get() = !imageUrl.isNullOrBlank() || !imageBase64.isNullOrBlank()
    }

    suspend fun generate(
        message: String,
        referenceUrl1: String? = null,
        referenceUrl2: String? = null
    ): kotlin.Result<Result> = withContext(Dispatchers.IO) {
        runCatching {
            val prompt = message.trim()
            require(prompt.isNotBlank()) { "描述不能为空" }

            val ref1 = referenceUrl1?.trim()?.takeIf { it.isNotBlank() }
            val ref2 = referenceUrl2?.trim()?.takeIf { it.isNotBlank() }
            val usePost = needsPostBody(ref1, ref2)

            val request = if (usePost) {
                val form = FormBody.Builder()
                    .add("message", prompt)
                    .apply {
                        ref1?.let { add("url1", it) }
                        ref2?.let { add("url2", it) }
                    }
                    .build()
                Request.Builder()
                    .url(ENDPOINT)
                    .post(form)
                    .header("Accept", "application/json, text/plain, */*")
                    .header("User-Agent", "MusicPlayer/1.0 (Android)")
                    .build()
            } else {
                val httpUrl = ENDPOINT.toHttpUrl().newBuilder()
                    .addQueryParameter("message", prompt)
                    .apply {
                        ref1?.let { addQueryParameter("url1", it) }
                        ref2?.let { addQueryParameter("url2", it) }
                    }
                    .build()
                Request.Builder()
                    .url(httpUrl)
                    .get()
                    .header("Accept", "application/json, text/plain, */*")
                    .header("User-Agent", "MusicPlayer/1.0 (Android)")
                    .build()
            }

            client.newCall(request).execute().use { response ->
                val body = response.body?.string().orEmpty()
                when (response.code) {
                    200 -> {
                        val parsed = parseImageResult(body)
                        if (!parsed.hasImage) {
                            Log.w(TAG, "200 but no image, body=${body.take(240)}")
                            error("生成成功但未解析到图片，请换描述重试")
                        }
                        parsed
                    }
                    403 -> error("无权限访问 AI 生图服务")
                    404 -> error("AI 生图接口不存在")
                    413 -> error("参考图过大，请换一张较小的图片")
                    429 -> error("请求过于频繁，请稍后再试")
                    in 500..599 -> error("AI 生图服务异常 (${response.code})")
                    else -> error("生图失败 HTTP ${response.code}")
                }
            }
        }
    }

    private fun needsPostBody(ref1: String?, ref2: String?): Boolean {
        fun heavy(s: String?): Boolean {
            if (s.isNullOrBlank()) return false
            if (s.startsWith("data:", ignoreCase = true)) return true
            // bare base64 without prefix
            if (s.length >= POST_THRESHOLD_CHARS && !s.startsWith("http", ignoreCase = true)) return true
            return s.length >= POST_THRESHOLD_CHARS
        }
        return heavy(ref1) || heavy(ref2)
    }

    /** Visible for unit tests. */
    fun parseImageResult(raw: String): Result {
        val text = raw.trim()
        if (text.isBlank()) return Result(raw = raw)

        // data:image/...;base64,...
        if (text.startsWith("data:image", ignoreCase = true)) {
            return Result(imageBase64 = text, raw = raw)
        }

        // Pure base64 blob (no prefix) — only accept if long enough
        if (text.length > 200 && text.matches(Regex("^[A-Za-z0-9+/=\\s]+$")) && !text.contains("http")) {
            return Result(imageBase64 = "data:image/png;base64,${text.replace("\\s".toRegex(), "")}", raw = raw)
        }

        // Plain URL
        if (looksLikeUrl(text)) {
            return Result(imageUrl = text, raw = raw)
        }

        // JSON
        if (text.startsWith("{") || text.startsWith("[")) {
            runCatching {
                if (text.startsWith("[")) {
                    val arr = JSONArray(text)
                    for (i in 0 until arr.length()) {
                        val item = arr.opt(i)
                        when (item) {
                            is String -> {
                                if (looksLikeUrl(item)) return Result(imageUrl = item, raw = raw)
                                if (item.startsWith("data:image", ignoreCase = true)) {
                                    return Result(imageBase64 = item, raw = raw)
                                }
                            }
                            is JSONObject -> extractFromJson(item)?.let { return it.copy(raw = raw) }
                        }
                    }
                } else {
                    extractFromJson(JSONObject(text))?.let { return it.copy(raw = raw) }
                }
            }
        }

        // HTML <img src="...">
        val imgMatcher = Pattern.compile(
            """(?i)<img[^>]+src\s*=\s*["']([^"']+)["']"""
        ).matcher(text)
        if (imgMatcher.find()) {
            val src = imgMatcher.group(1)?.trim().orEmpty()
            if (looksLikeUrl(src)) return Result(imageUrl = src, raw = raw)
            if (src.startsWith("data:image", ignoreCase = true)) {
                return Result(imageBase64 = src, raw = raw)
            }
        }

        // First http(s) URL in free text
        val urlMatcher = Pattern.compile(
            """https?://[^\s"'<>\\]+""",
            Pattern.CASE_INSENSITIVE
        ).matcher(text)
        if (urlMatcher.find()) {
            val u = urlMatcher.group()?.trim()?.trimEnd(',', ';', ')', ']')
            if (!u.isNullOrBlank() && looksLikeUrl(u)) {
                return Result(imageUrl = u, raw = raw)
            }
        }

        return Result(raw = raw)
    }

    private fun extractFromJson(obj: JSONObject): Result? {
        val keys = listOf(
            "url", "image", "img", "src", "link", "pic", "picUrl", "imageUrl",
            "img_url", "image_url", "result", "data", "file", "path", "content"
        )
        for (key in keys) {
            if (!obj.has(key)) continue
            when (val value = obj.opt(key)) {
                is String -> {
                    val s = value.trim()
                    if (looksLikeUrl(s)) return Result(imageUrl = s)
                    if (s.startsWith("data:image", ignoreCase = true)) return Result(imageBase64 = s)
                    // Nested JSON string
                    if (s.startsWith("{")) {
                        runCatching { extractFromJson(JSONObject(s)) }.getOrNull()?.let { return it }
                    }
                }
                is JSONObject -> extractFromJson(value)?.let { return it }
                is JSONArray -> {
                    for (i in 0 until value.length()) {
                        when (val item = value.opt(i)) {
                            is String -> {
                                val s = item.trim()
                                if (looksLikeUrl(s)) return Result(imageUrl = s)
                                if (s.startsWith("data:image", ignoreCase = true)) {
                                    return Result(imageBase64 = s)
                                }
                            }
                            is JSONObject -> extractFromJson(item)?.let { return it }
                        }
                    }
                }
            }
        }
        // code/msg envelope with nested data
        obj.optJSONObject("data")?.let { extractFromJson(it) }?.let { return it }
        return null
    }

    private fun looksLikeUrl(value: String): Boolean {
        val v = value.trim()
        return v.startsWith("http://", ignoreCase = true) ||
            v.startsWith("https://", ignoreCase = true)
    }
}
