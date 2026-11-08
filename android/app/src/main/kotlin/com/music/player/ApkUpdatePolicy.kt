package com.music.player

data class InstalledApk(val packageName: String, val versionCode: Long, val signers: Set<String>)
data class UpdateRejection(val code: String, val message: String)

/** Validate identity before asking Android to install an in-place update. */
object ApkUpdatePolicy {
    fun rejection(installed: InstalledApk, archive: InstalledApk): UpdateRejection? = when {
        installed.packageName != archive.packageName -> UpdateRejection(
            "WRONG_PACKAGE", "安装包与当前应用不属于同一版本渠道，已停止安装，避免生成另一个应用。请在正式版中检查更新。"
        )
        archive.signers.isEmpty() || installed.signers.isEmpty() || archive.signers != installed.signers ->
            UpdateRejection("WRONG_SIGNATURE", "安装包签名与当前应用不一致，无法覆盖更新。请保留当前应用及数据，并联系开发者。")
        archive.versionCode <= installed.versionCode -> UpdateRejection(
            "NOT_NEWER", "安装包构建号不高于当前版本，请重新检查更新并下载适合当前设备的安装包。"
        )
        else -> null
    }
}
