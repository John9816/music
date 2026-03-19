package com.music.player.update

import android.app.Activity
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.repository.AppVersionInfo

fun Activity.showAppUpdateDialog(
    currentVersion: String,
    currentBuildNumber: Int,
    latest: AppVersionInfo,
    force: Boolean,
    onConfirm: () -> Unit,
    onLater: (() -> Unit)? = null
) {
    val message = buildString {
        append("Local: ").append(currentVersion).append(" (").append(currentBuildNumber).append(")")
        append("\nRemote: ").append(latest.version).append(" (").append(latest.buildNumber).append(")")
        if (!latest.description.isNullOrBlank()) {
            append("\n\n").append(latest.description.trim())
        }
    }

    val dialog = MaterialAlertDialogBuilder(this)
        .setTitle(R.string.update_title)
        .setMessage(message)
        .setPositiveButton(R.string.update_download) { _, _ -> onConfirm() }

    if (force) {
        dialog.setCancelable(false)
        dialog.setNegativeButton(R.string.update_exit) { _, _ -> finishAffinity() }
    } else {
        dialog.setNegativeButton(R.string.update_later) { _, _ -> onLater?.invoke() }
    }

    dialog.show()
}
