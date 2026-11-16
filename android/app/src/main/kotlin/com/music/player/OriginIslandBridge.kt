package com.music.player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList

/**
 * vivo OriginOS 原子岛（vivo 内部代号 Super Island）的本地发送器。
 *
 * 协议并非 vivo 公开 SDK，而是社区从 OriginOS 框架逆向得到的 notification
 * extras 格式。所有键都以 `notification.superx.*` / `island.superx.*` 命名，
 * 通过一条普通通知投递：在支持原子岛的 ROM 上会被渲染成挖孔周围的胶囊，
 * 在不支持的设备/其他品牌上则只是一条普通通知，不会产生异常。
 *
 * wire format 移植自 MIT 许可的开源实现，保留署名：
 *   Copyright (c) 2026 cameleonnbss
 *   https://github.com/cameleonnbss/originos-toolkit
 */
object OriginIslandBridge {
    const val CHANNEL: String = "com.music.player/origin_island"
    private const val CHANNEL_ID = "duckmusic_origin_island"
    private const val NOTIFICATION_ID = 3101

    private const val OP_SHOW = 0
    private const val OP_END = 2
    /** 框架匹配用的场景名，社区逆向得出；上游在所有卡片上都用它。 */
    private const val SCENE = "TRAIN"
    private const val FALLBACK_ACCENT = 0xFF80CBC4.toInt()

    private enum class Template(val id: Int) {
        RHYTHM(1), PROGRESS(2), LOADING(3), TEXT_ICON(4), ICON_TEXT(5), CAPSULE(6)
    }

    private data class Request(
        val title: String,
        val content: String,
        val subText: String?,
        val template: Template,
        val progress: Int,
        val progressMax: Int,
        val accentColor: Int,
        val rightText: String?,
    ) {
        val progressPercent: Int
            get() = if (progressMax > 0) {
                ((progress.toLong() * 100) / progressMax).toInt().coerceIn(0, 100)
            } else 0
    }

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, context.applicationContext, result) }
    }

    private fun handle(call: MethodCall, context: Context, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isVivo())
            "show" -> {
                val title = call.argument<String>("title").orEmpty()
                val content = call.argument<String>("content").orEmpty()
                val subText = call.argument<String>("subText")
                val playing = call.argument<Boolean>("playing") == true
                val progress = call.argument<Int>("progress") ?: 0
                val progressMax = call.argument<Int>("progressMax") ?: 0
                val accentColor = call.argument<Int>("accentColor") ?: FALLBACK_ACCENT
                val rightText = call.argument<String>("rightText")
                val useProgress = playing && progressMax > 0 && progress in 1 until progressMax
                val request = Request(
                    title = title,
                    content = content,
                    subText = subText,
                    template = if (useProgress) Template.PROGRESS else Template.TEXT_ICON,
                    progress = progress,
                    progressMax = progressMax,
                    accentColor = accentColor,
                    rightText = rightText,
                )
                result.success(post(context, request))
            }
            "hide" -> {
                hide(context)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    fun isVivo(): Boolean {
        val brand = Build.BRAND.orEmpty()
        val manufacturer = Build.MANUFACTURER.orEmpty()
        return brand.contains("vivo", ignoreCase = true) ||
            brand.contains("iqoo", ignoreCase = true) ||
            manufacturer.contains("vivo", ignoreCase = true)
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "原子岛播放胶囊",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "在屏幕挖孔周围显示当前播放进度"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun post(context: Context, request: Request): Boolean {
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        registerScene(context)
        val icon = Icon.createWithResource(context, R.drawable.ic_notification_music)
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_music)
            .setContentTitle(request.title)
            .setContentText(request.content)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        builder.extras.putAll(buildExtras(request, icon))
        return try {
            manager.notify(NOTIFICATION_ID, builder.build())
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 先写 operation=2 让胶囊优雅收起，再取消通知。 */
    private fun hide(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        try {
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification_music)
            builder.extras.putAll(buildEndExtras())
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: Exception) {
            // 卸载提示是尽力而为；下面的 cancel 才是保证。
        }
        manager.cancel(NOTIFICATION_ID)
    }

    private fun buildExtras(request: Request, smallIcon: Icon): Bundle {
        val out = Bundle()
        val progressMode = request.template == Template.PROGRESS

        out.putInt("notification.superx.operation", OP_SHOW)
        out.putBoolean("notification.superx.showNotify", true)
        out.putInt("notification.superx.template", if (progressMode) 2 else 1)
        out.putString("notification.superx.scene", SCENE)
        out.putInt("notification.superx.changedRecord", 0)

        // baseInfos：卡片展开后的标题、内容、图标与副文本。
        val baseInfos = Bundle()
        baseInfos.putCharSequence("notification.superx.baseInfos.title", request.title)
        baseInfos.putCharSequence("notification.superx.baseInfos.content", request.content)
        baseInfos.putParcelable("notification.superx.baseInfos.icon", smallIcon)
        request.subText?.takeIf { it.isNotBlank() }?.let { sub ->
            baseInfos.putInt("notification.superx.baseInfos.subInfo", 1)
            baseInfos.putString("notification.superx.baseInfos.subText", sub)
        }
        out.putBundle("notification.superx.baseInfos", baseInfos)

        // capsule：决定模板是否解析，缺了它岛上不会出胶囊。
        val capsule = Bundle()
        capsule.putInt("notification.superx.capsule.state", 1)
        capsule.putCharSequence("notification.superx.capsule.content", request.title)
        capsule.putParcelable("notification.superx.capsule.icon", smallIcon)
        out.putBundle("notification.superx.capsule", capsule)

        // infos：模板相关的负载（进度百分比 / 颜色 / 节点图标，或描述 / 主信息）。
        val infos = Bundle()
        if (progressMode) {
            infos.putInt("notification.superx.infos.progress", request.progressPercent)
            infos.putInt("notification.superx.infos.progressColor", request.accentColor)
            val nodes = ArrayList<Icon>()
            nodes.add(smallIcon)
            nodes.add(smallIcon)
            infos.putParcelableArrayList("notification.superx.infos.nodeIcon", nodes)
            infos.putParcelable("notification.superx.infos.indicatorIcon", smallIcon)
            infos.putInt("notification.superx.infos.indicatorLoc", 1)
        } else {
            infos.putString(
                "notification.superx.infos.describe",
                request.subText?.takeIf { it.isNotBlank() } ?: request.title,
            )
            infos.putString("notification.superx.infos.coreInfo", request.content)
            infos.putParcelable("notification.superx.infos.image", smallIcon)
        }
        out.putBundle("notification.superx.infos", infos)

        // shortInfos：框架展开卡片时要的同一批字段（Short 后缀）。
        val shortInfos = Bundle()
        shortInfos.putString(
            "notification.superx.shortInfos.describeShort",
            request.subText?.takeIf { it.isNotBlank() } ?: request.title,
        )
        shortInfos.putString("notification.superx.shortInfos.coreInfoShort", request.content)
        shortInfos.putParcelable("notification.superx.shortInfos.image", smallIcon)
        out.putBundle("notification.superx.shortInfos", shortInfos)

        // island：左侧模板固定 1，右侧按播放/暂停选进度或图文。
        val island = Bundle()
        island.putInt("island.superx.leftTemplate", 1)
        island.putInt("island.superx.rightTemplate", request.template.id)
        val left = Bundle()
        left.putString("island.superx.leftInfo.content", request.title)
        left.putParcelable("island.superx.leftInfo.icon", smallIcon)
        island.putBundle("island.superx.leftInfo", left)
        val right = Bundle()
        if (progressMode) {
            right.putInt("island.superx.rightInfo.progressValue", request.progressPercent)
            right.putInt("island.superx.rightInfo.progressState", 0)
            right.putInt("island.superx.rightInfo.progressColor", request.accentColor)
        } else {
            right.putString(
                "island.superx.rightInfo.content",
                request.rightText?.takeIf { it.isNotBlank() } ?: request.content,
            )
            right.putParcelable("island.superx.rightInfo.icon", smallIcon)
        }
        island.putBundle("island.superx.rightInfo", right)
        out.putBundle("notification.superx.island", island)

        return out
    }

    private fun buildEndExtras(): Bundle = Bundle().apply {
        putInt("notification.superx.operation", OP_END)
    }

    /** vivo 自家应用会先注册场景列表；用反射跟随它，缺席时忽略即可。 */
    private fun registerScene(context: Context) {
        try {
            val method = NotificationManager::class.java.getMethod(
                "setSuperXInfosSceneList",
                MutableList::class.java,
                MutableList::class.java,
                MutableList::class.java,
                MutableList::class.java,
            )
            method.invoke(
                context.getSystemService(Context.NOTIFICATION_SERVICE),
                arrayListOf(SCENE),
                arrayListOf("true"),
                arrayListOf(context.packageName),
                arrayListOf("true"),
            )
        } catch (_: Exception) {
            // 非 vivo ROM 上没有这个方法；extras 本身仍然携带负载。
        }
    }
}
