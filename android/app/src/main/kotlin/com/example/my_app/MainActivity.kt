package com.example.my_app

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var fgChannel: MethodChannel? = null
    private var pipChannel: MethodChannel? = null
    private var callActive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        fgChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seeu/call_fg")
        fgChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    val title = call.argument<String>("title") ?: "Звонок"
                    val body  = call.argument<String>("body")  ?: ""
                    val intent = CallForegroundService.startIntent(this, title, body)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopForeground" -> {
                    stopService(Intent(this, CallForegroundService::class.java))
                    result.success(null)
                }
                "setCallActive" -> {
                    callActive = call.argument<Boolean>("active") ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seeu/pip")
        pipChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    enterPipMode()
                    result.success(null)
                }
                "exitPip" -> {
                    // Android не имеет API выхода из PiP — окно закрывается само
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPipMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        }
    }

    /** Автоматический вход в PiP при нажатии кнопки «Домой» во время активного звонка. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (callActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPipMode()
        }
    }

    /** Уведомляем Flutter об изменении режима PiP. */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }
}
