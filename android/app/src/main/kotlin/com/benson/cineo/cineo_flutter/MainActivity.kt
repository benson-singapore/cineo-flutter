package com.benson.cineo.cineo_flutter

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val pictureInPictureChannel = "com.benson.cineo/picture_in_picture"
    private lateinit var pictureInPictureMethodChannel: MethodChannel
    private val pictureInPictureActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            intent.getStringExtra(EXTRA_PICTURE_IN_PICTURE_ACTION)?.let { action ->
                pictureInPictureMethodChannel.invokeMethod("pictureInPictureAction", action)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pictureInPictureMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pictureInPictureChannel,
        )
        pictureInPictureMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isPictureInPictureAvailable())
                "enter" -> {
                    if (!isPictureInPictureAvailable()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(enterCineoPictureInPicture(call.arguments as? Map<*, *>))
                }
                "openSystemPlayer" -> result.success(
                    openSystemPlayer(call.arguments as? Map<*, *>),
                )
                "update" -> updatePictureInPictureParams(call.arguments as? Map<*, *>).also {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        val actionFilter = IntentFilter("$packageName.picture_in_picture_action")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                pictureInPictureActionReceiver,
                actionFilter,
                RECEIVER_NOT_EXPORTED,
            )
        } else {
            registerReceiver(pictureInPictureActionReceiver, actionFilter)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(pictureInPictureActionReceiver)
        super.onDestroy()
    }

    private fun isPictureInPictureAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun openSystemPlayer(arguments: Map<*, *>?): Boolean {
        val url = arguments?.get("url") as? String ?: return false
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = android.net.Uri.parse(url)
            type = "video/*"
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
            true
        } else {
            false
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pictureInPictureMethodChannel.invokeMethod(
            "pictureInPictureModeChanged",
            isInPictureInPictureMode,
        )
    }

    private fun enterCineoPictureInPicture(arguments: Map<*, *>?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val aspectRatio = arguments?.get("aspectRatio") as? Double ?: (16.0 / 9.0)
        val safeRatio = aspectRatio.coerceIn(0.418, 2.390)
        val denominator = 1000
        val numerator = (safeRatio * denominator).toInt().coerceAtLeast(1)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(numerator, denominator))
            .setActions(buildPictureInPictureActions(arguments))
            .build()
        return enterPictureInPictureMode(params)
    }

    private fun updatePictureInPictureParams(arguments: Map<*, *>?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isInPictureInPictureMode) return
        val aspectRatio = arguments?.get("aspectRatio") as? Double ?: (16.0 / 9.0)
        val safeRatio = aspectRatio.coerceIn(0.418, 2.390)
        val denominator = 1000
        val numerator = (safeRatio * denominator).toInt().coerceAtLeast(1)
        setPictureInPictureParams(
            PictureInPictureParams.Builder()
                .setAspectRatio(Rational(numerator, denominator))
                .setActions(buildPictureInPictureActions(arguments))
                .build(),
        )
    }

    private fun buildPictureInPictureActions(arguments: Map<*, *>?): List<RemoteAction> {
        val isPlaying = arguments?.get("isPlaying") as? Boolean ?: false
        return listOf(
            pictureInPictureAction(
                "toggle",
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "暂停" else "播放",
            ),
        )
    }

    private fun pictureInPictureAction(action: String, icon: Int, title: String): RemoteAction {
        val intent = Intent("$packageName.picture_in_picture_action")
            .setPackage(packageName)
            .putExtra(EXTRA_PICTURE_IN_PICTURE_ACTION, action)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return RemoteAction(Icon.createWithResource(this, icon), title, title, pendingIntent)
    }

    private companion object {
        const val EXTRA_PICTURE_IN_PICTURE_ACTION = "picture_in_picture_action"
    }
}
