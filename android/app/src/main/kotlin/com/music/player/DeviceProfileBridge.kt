package com.music.player

import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 统一的设备家族探测。
 *
 * vivo/iQOO 的原子岛、OPPO/一加/realme 的流体云与三段式拨杆，都依赖
 * "品牌家族" 判断；此前该逻辑只存在于 [OriginIslandBridge.isVivo] 中。
 * 这里集中提供，避免每个厂商特性各写一份、判定不一致。
 *
 * 只读静态系统属性，不需要任何运行时权限，不产生可见副作用。
 */
object DeviceProfileBridge {
    const val CHANNEL: String = "com.music.player/device_profile"
    const val FAMILY_VIVO: String = "vivo"
    const val FAMILY_OPLUS: String = "oplus"
    const val FAMILY_OTHER: String = "other"

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "profile" -> result.success(profile(context.applicationContext))
                    else -> result.notImplemented()
                }
            }
    }

    fun profile(context: Context): Map<String, Any?> {
        val brand = Build.BRAND.orEmpty()
        val manufacturer = Build.MANUFACTURER.orEmpty()
        val vivo = isVivo(brand, manufacturer)
        val oplus = isOplus(brand, manufacturer)
        val family = when {
            vivo -> FAMILY_VIVO
            oplus -> FAMILY_OPLUS
            else -> FAMILY_OTHER
        }
        return mapOf(
            "brand" to brand,
            "manufacturer" to manufacturer,
            "model" to Build.MODEL.orEmpty(),
            "family" to family,
            "isVivo" to vivo,
            "isOplus" to oplus,
            // 一加国行 ColorOS / 海外 OxygenOS 都带 oplusrom 属性。
            "oplusVersion" to systemProperty("ro.build.version.oplusrom"),
        )
    }

    fun isVivo(): Boolean = isVivo(Build.BRAND, Build.MANUFACTURER)

    private fun isVivo(brand: String?, manufacturer: String?): Boolean {
        val b = brand.orEmpty()
        val m = manufacturer.orEmpty()
        return b.contains("vivo", ignoreCase = true) ||
            b.contains("iqoo", ignoreCase = true) ||
            m.contains("vivo", ignoreCase = true)
    }

    fun isOplus(): Boolean = isOplus(Build.BRAND, Build.MANUFACTURER)

    private fun isOplus(brand: String?, manufacturer: String?): Boolean {
        val b = brand.orEmpty()
        val m = manufacturer.orEmpty()
        if (b.contains("oneplus", ignoreCase = true) ||
            b.contains("oppo", ignoreCase = true) ||
            b.contains("realme", ignoreCase = true) ||
            m.contains("oneplus", ignoreCase = true) ||
            m.contains("oppo", ignoreCase = true) ||
            m.contains("realme", ignoreCase = true)
        ) {
            return true
        }
        // 部分机型 MANUFACTURER 被改成通用值，改用 ROM 属性兜底。
        return !systemProperty("ro.build.version.oplusrom").isNullOrBlank() ||
            !systemProperty("ro.build.version.opporom").isNullOrBlank()
    }

    private fun systemProperty(key: String): String? = try {
        val clazz = Class.forName("android.os.SystemProperties")
        val get = clazz.getMethod("get", String::class.java)
        get.invoke(null, key) as? String
    } catch (_: Exception) {
        null
    }
}
