package com.music.player.ui.tools

import android.content.Context
import android.content.Intent
import com.music.player.R
import com.music.player.ui.activity.AiDrawActivity
import com.music.player.ui.activity.RadioActivity
import com.music.player.ui.activity.TvLiveActivity
import com.music.player.ui.activity.TvVodActivity
import com.music.player.ui.activity.VideoParseActivity

enum class ToolGroup {
    LISTEN,
    CREATE,
    UTILITY
}

data class ToolItem(
    val id: String,
    val group: ToolGroup,
    val titleRes: Int,
    val subtitleRes: Int,
    val iconRes: Int,
    val enabled: Boolean = true,
    val intentFactory: (Context) -> Intent
)

object ToolsCatalog {

    fun all(): List<ToolItem> = listOf(
        ToolItem(
            id = "radio",
            group = ToolGroup.LISTEN,
            titleRes = R.string.tools_radio_title,
            subtitleRes = R.string.tools_radio_subtitle,
            iconRes = R.drawable.ic_cymusic_radio_24,
            intentFactory = { RadioActivity.intent(it) }
        ),
        ToolItem(
            id = "tv_live",
            group = ToolGroup.LISTEN,
            titleRes = R.string.tools_tv_live_title,
            subtitleRes = R.string.tools_tv_live_subtitle,
            iconRes = R.drawable.ic_cymusic_radio_24,
            intentFactory = { TvLiveActivity.intent(it) }
        ),
        ToolItem(
            id = "tv_vod",
            group = ToolGroup.LISTEN,
            titleRes = R.string.tools_tv_vod_title,
            subtitleRes = R.string.tools_tv_vod_subtitle,
            iconRes = R.drawable.ic_tv_24,
            intentFactory = { TvVodActivity.intent(it) }
        ),
        ToolItem(
            id = "ai_draw",
            group = ToolGroup.CREATE,
            titleRes = R.string.ai_draw_title,
            subtitleRes = R.string.tools_ai_draw_subtitle,
            iconRes = R.drawable.ic_music_note_24,
            intentFactory = { AiDrawActivity.intent(it) }
        ),
        ToolItem(
            id = "video_parse",
            group = ToolGroup.UTILITY,
            titleRes = R.string.tools_video_parse_title,
            subtitleRes = R.string.tools_video_parse_subtitle,
            iconRes = R.drawable.ic_download_24,
            enabled = true,
            intentFactory = { VideoParseActivity.intent(it) }
        )
    )

    fun groupTitleRes(group: ToolGroup): Int = when (group) {
        ToolGroup.LISTEN -> R.string.tools_group_listen
        ToolGroup.CREATE -> R.string.tools_group_create
        ToolGroup.UTILITY -> R.string.tools_group_utility
    }
}

