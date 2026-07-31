package com.music.player.data.live

object TvLogoUrl {

    private const val UNRELIABLE_LOGO_PREFIX = "https://live.fanmingming.cn/tv/"
    private const val CDN_LOGO_PREFIX =
        "https://cdn.jsdelivr.net/gh/fanmingming/live@main/tv/"

    fun resolve(rawUrl: String): String {
        val url = rawUrl.trim()
        return if (url.startsWith(UNRELIABLE_LOGO_PREFIX, ignoreCase = true)) {
            CDN_LOGO_PREFIX + url.substring(UNRELIABLE_LOGO_PREFIX.length)
        } else {
            url
        }
    }
}
