package com.example.my_app

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.util.Rational
import android.view.View
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service requires the host Activity to be AudioServiceActivity (it wires
// the MediaBrowserService binding). With a plain FlutterActivity, AudioService.init
// throws on Android → main() aborts before runApp() → black screen.
class MainActivity : AudioServiceActivity() {

    private var fgChannel: MethodChannel? = null
    private var pipChannel: MethodChannel? = null      // seeu/pip  — for calls
    private var videoPipChannel: MethodChannel? = null // seeu/video_pip — for videos
    private var callActive = false
    private var videoActive = false
    private var pipKind = ""  // "call" | "video" — which kind entered PiP last
    // Реальные пропорции текущего видео (по умолчанию 16:9). Обновляются из
    // Flutter через setVideoActive, чтобы PiP-окно для вертикальных reels (9:16)
    // и кинематографичных (21:9) видео не растягивалось.
    private var videoAspectW = 16
    private var videoAspectH = 9

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register AR face mask platform view
        flutterEngine.platformViewsController.registry
            .registerViewFactory(
                "seeu/ar_face_mask",
                ARFaceMaskViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )

        // ── Call foreground service channel ───────────────────────────────
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
                    updatePipParams()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── Call PiP channel ──────────────────────────────────────────────
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seeu/pip")
        pipChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    pipKind = "call"
                    enterCallPipMode()
                    result.success(null)
                }
                "exitPip" -> result.success(null)
                else -> result.notImplemented()
            }
        }

        // ── Video PiP channel ─────────────────────────────────────────────
        videoPipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seeu/video_pip")
        videoPipChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVideoActive" -> {
                    videoActive = call.argument<Boolean>("active") ?: false
                    call.argument<Int>("aspectW")?.let { if (it > 0) videoAspectW = it }
                    call.argument<Int>("aspectH")?.let { if (it > 0) videoAspectH = it }
                    updatePipParams()
                    result.success(null)
                }
                "startVideoPip" -> {
                    // Android: PiP is Activity-level; just trigger enter.
                    call.argument<Int>("aspectW")?.let { if (it > 0) videoAspectW = it }
                    call.argument<Int>("aspectH")?.let { if (it > 0) videoAspectH = it }
                    if (videoActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        pipKind = "video"
                        enterVideoPipMode()
                    }
                    result.success(null)
                }
                "exitPip" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }

    // ── PiP params ────────────────────────────────────────────────────────

    /**
     * On Android 12+ sets autoEnter for the active PiP kind:
     *   - call: 9:16 portrait
     *   - video: 16:9 landscape
     */
    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val builder = PictureInPictureParams.Builder()
            if (callActive) {
                builder.setAspectRatio(Rational(9, 16))
            } else {
                builder.setAspectRatio(safeRational(videoAspectW, videoAspectH))
                // sourceRectHint делает morph-анимацию входа в PiP плавной —
                // система анимирует из прямоугольника контента, а не из угла.
                videoSourceRectHint()?.let { builder.setSourceRectHint(it) }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(callActive || videoActive)
            }
            try { setPictureInPictureParams(builder.build()) } catch (_: Exception) {}
        }
    }

    private fun enterCallPipMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            // Старые/урезанные прошивки могут отклонить вход в PiP — не падаем.
            try { enterPictureInPictureMode(params) } catch (_: Exception) {}
        }
    }

    private fun enterVideoPipMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(safeRational(videoAspectW, videoAspectH))
            videoSourceRectHint()?.let { builder.setSourceRectHint(it) }
            // Если устройство в данный момент не может войти в PiP (заблокирован
            // экран, неподдерживаемое состояние) — просто игнорируем, аудио при
            // этом продолжает играть в фоне.
            try { enterPictureInPictureMode(builder.build()) } catch (_: Exception) {}
        }
    }

    /** Прямоугольник контента (Flutter view) в координатах окна — для sourceRectHint. */
    private fun videoSourceRectHint(): Rect? {
        return try {
            val content = findViewById<View>(android.R.id.content) ?: return null
            val r = Rect()
            if (content.getGlobalVisibleRect(r) && r.width() > 0 && r.height() > 0) r else null
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Android требует пропорции PiP в диапазоне ~[0.42, 2.39]. Зажимаем реальные
     * пропорции видео в этот диапазон, иначе setAspectRatio бросит IllegalArgument.
     */
    private fun safeRational(w: Int, h: Int): Rational {
        val ww = if (w > 0) w else 16
        val hh = if (h > 0) h else 9
        var ratio = ww.toDouble() / hh.toDouble()
        if (ratio < 0.42) ratio = 0.42
        if (ratio > 2.38) ratio = 2.38
        return Rational((ratio * 1000).toInt(), 1000)
    }

    /**
     * Android 8-11 button nav: Home button → onUserLeaveHint.
     * Android 12+ gesture nav: handled by setAutoEnterEnabled in updatePipParams.
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        when {
            callActive -> {
                pipKind = "call"
                enterCallPipMode()
            }
            videoActive -> {
                pipKind = "video"
                enterVideoPipMode()
            }
        }
    }

    /** Route pipModeChanged to the correct Flutter channel. */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (pipKind == "video") {
            videoPipChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
        } else {
            pipChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
        }
        if (!isInPictureInPictureMode) pipKind = ""
    }
}
