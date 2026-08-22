package com.benson.cineo.cineo_flutter

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val pictureInPictureChannel = "com.benson.cineo/picture_in_picture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pictureInPictureChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isPictureInPictureAvailable())
                "enter" -> {
                    if (!isPictureInPictureAvailable()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val requestedRatio = call.argument<Double>("aspectRatio") ?: (16.0 / 9.0)
                    result.success(enterCineoPictureInPicture(requestedRatio))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPictureInPictureAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun enterCineoPictureInPicture(aspectRatio: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val safeRatio = aspectRatio.coerceIn(0.418, 2.390)
        val denominator = 1000
        val numerator = (safeRatio * denominator).toInt().coerceAtLeast(1)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(numerator, denominator))
            .build()
        return enterPictureInPictureMode(params)
    }
}
