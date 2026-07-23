package com.music.player.ui.util

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.core.content.ContextCompat
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.music.player.R

/**
 * Requests every permission the app needs as early as possible after login:
 * - [Manifest.permission.POST_NOTIFICATIONS] (API 33+) for the media notification
 * - "Install unknown apps" for in-app update install handoff (settings screen, not a runtime grant)
 *
 * Runtime permissions are requested first; install-source guidance follows when needed.
 */
class AppPermissionBootstrap(
    private val activity: ComponentActivity
) {

    companion object {
        private const val PREFS = "app_permission_bootstrap"
        private const val KEY_RUNTIME_ASKED = "runtime_asked"
        private const val KEY_INSTALL_PROMPTED = "install_prompted"
    }

    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var installDialog: AlertDialog? = null
    private var forceRound = false

    private val runtimeLauncher =
        activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            // Regardless of grant/deny, continue to special permissions.
            maybePromptInstallPackages(force = forceRound)
            forceRound = false
        }

    private val installSettingsLauncher =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            // User returned from settings; no further UI unless still missing and force.
        }

    /**
     * @param force when true (fresh login), re-prompt even if we asked earlier this install.
     *              Still skips if the permission is already granted.
     */
    fun requestAllNeeded(force: Boolean = false) {
        forceRound = force
        val missingRuntime = missingRuntimePermissions()
        if (missingRuntime.isNotEmpty()) {
            val alreadyAsked = prefs.getBoolean(KEY_RUNTIME_ASKED, false)
            if (force || !alreadyAsked) {
                prefs.edit().putBoolean(KEY_RUNTIME_ASKED, true).apply()
                runtimeLauncher.launch(missingRuntime.toTypedArray())
                return
            }
        }
        maybePromptInstallPackages(force = force)
    }

    fun missingRuntimePermissions(): List<String> {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33) {
            if (!isGranted(Manifest.permission.POST_NOTIFICATIONS)) {
                needed += Manifest.permission.POST_NOTIFICATIONS
            }
        }
        return needed
    }

    fun needsInstallPackagesPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return !activity.packageManager.canRequestPackageInstalls()
    }

    private fun maybePromptInstallPackages(force: Boolean) {
        if (!needsInstallPackagesPermission()) return
        val prompted = prefs.getBoolean(KEY_INSTALL_PROMPTED, false)
        if (!force && prompted) return
        if (installDialog?.isShowing == true) return

        prefs.edit().putBoolean(KEY_INSTALL_PROMPTED, true).apply()
        installDialog = MaterialAlertDialogBuilder(activity)
            .setTitle(R.string.permission_install_title)
            .setMessage(R.string.permission_install_message)
            .setPositiveButton(R.string.permission_install_allow) { _, _ ->
                openInstallPackagesSettings()
            }
            .setNegativeButton(R.string.permission_later, null)
            .setOnDismissListener { installDialog = null }
            .show()
    }

    private fun openInstallPackagesSettings() {
        val appSettings = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}")
        )
        val launched = runCatching {
            installSettingsLauncher.launch(appSettings)
        }.isSuccess || runCatching {
            installSettingsLauncher.launch(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }.isSuccess
        if (!launched) {
            runCatching {
                activity.startActivity(appSettings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }

    private fun isGranted(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED
    }
}
