package com.music.player.update

import android.app.Activity
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R
import com.music.player.data.repository.AppVersionInfo

object AppUpdateDialogs {
    fun show(
        activity: Activity,
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

        val dialog = MaterialAlertDialogBuilder(activity)
            .setTitle(R.string.update_title)
            .setMessage(message)
            .setPositiveButton(R.string.update_download) { _, _ -> onConfirm() }

        if (force) {
            dialog.setCancelable(false)
            dialog.setNegativeButton(R.string.update_exit) { _, _ -> activity.finishAffinity() }
        } else {
            dialog.setNegativeButton(R.string.update_later) { _, _ -> onLater?.invoke() }
        }

        dialog.show()
    }
}
