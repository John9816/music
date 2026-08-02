package com.music.player.update

import android.app.Activity
import android.text.method.ScrollingMovementMethod
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textview.MaterialTextView
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
            append(
                activity.getString(
                    R.string.update_dialog_current_version,
                    currentVersion,
                    currentBuildNumber
                )
            )
            append("\n")
            append(activity.getString(R.string.update_dialog_remote_version, latest.version))
            if (!latest.description.isNullOrBlank()) {
                append("\n\n").append(latest.description.trim())
            }
        }

        val body = MaterialTextView(activity).apply {
            text = message
            setLineSpacing(0f, 1.15f)
            setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyMedium)
            setTextColor(resolveBodyTextColor(activity))
            maxHeight = (MAX_BODY_HEIGHT_DP * activity.resources.displayMetrics.density).toInt()
            movementMethod = ScrollingMovementMethod()
            isVerticalScrollBarEnabled = true
        }
        val dialog = MaterialAlertDialogBuilder(activity)
            .setTitle(R.string.update_title)
            .setView(body)
            .setPositiveButton(R.string.update_download) { _, _ -> onConfirm() }

        if (force) {
            dialog.setCancelable(false)
            dialog.setNegativeButton(R.string.update_exit) { _, _ -> activity.finishAffinity() }
        } else {
            dialog.setNegativeButton(R.string.update_later) { _, _ -> onLater?.invoke() }
        }

        dialog.show()
    }

    private fun resolveBodyTextColor(activity: Activity): Int {
        val ta = activity.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary))
        return try {
            ta.getColor(0, 0xFF000000.toInt())
        } finally {
            ta.recycle()
        }
    }

    private const val MAX_BODY_HEIGHT_DP = 340
}
