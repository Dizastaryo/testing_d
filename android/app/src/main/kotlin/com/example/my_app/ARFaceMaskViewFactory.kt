package com.example.my_app

import android.content.Context
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

// TEMP (Android build): the real Sceneform-based 3D AR face mask renderer was
// disabled. The community `com.google.ar.sceneform.ux:1.17.1` fork pulls the
// legacy `com.android.support` library (AndroidX duplicate-class conflict) and
// its API (setIsFilamentGltf / collisionShape / …) no longer matches, so it
// fails to compile. This stub keeps the platform-view contract intact —
// viewType "seeu/ar_face_mask", channel "seeu/ar_face_mask_<id>", methods
// loadMask/clearMask/captureSnapshot — but renders a transparent view (the
// camera preview shows through) and the methods are no-ops. 2D filters/masks
// (Flutter-side) are unaffected. Restore the real renderer once the Sceneform
// dependency is pinned to a compatible build.
class ARFaceMaskViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ARFaceMaskPlatformView(context, viewId, messenger)
    }
}

class ARFaceMaskPlatformView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
) : PlatformView {

    private val channel = MethodChannel(messenger, "seeu/ar_face_mask_$viewId")
    private val view = View(context).apply {
        // Transparent so the camera preview behind the AndroidView stays visible.
        setBackgroundColor(0x00000000)
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "loadMask", "clearMask" -> result.success(null)
                // No native render → no snapshot. Flutter falls back to the
                // plain camera frame when this returns null.
                "captureSnapshot" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }

    override fun getView(): View = view

    override fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
