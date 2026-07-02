import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var pipChannel: FlutterMethodChannel?
  private var videoPipChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      // Register AR face mask platform view
      let arFactory = ARFaceMaskViewFactory(messenger: controller.binaryMessenger)
      let registrar = self.registrar(forPlugin: "ARFaceMaskView")!
      registrar.register(arFactory, withId: "seeu/ar_face_mask")

      // ── Call PiP channel (seeu/pip) ─────────────────────────────────────
      pipChannel = FlutterMethodChannel(
        name: "seeu/pip",
        binaryMessenger: controller.binaryMessenger
      )
      pipChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "prepareCallPip":
          if #available(iOS 15.0, *) {
            let args = call.arguments as? [String: Any]
            let avatarUrl = args?["avatarUrl"] as? String
            let username  = args?["username"]  as? String ?? ""
            let kind      = args?["kind"]      as? String ?? "voice"
            PipManager.shared.prepareCall(
              avatarUrl: (avatarUrl?.isEmpty == false) ? avatarUrl : nil,
              username: username,
              kind: kind,
              onReturn: { [weak self] in
                self?.pipChannel?.invokeMethod("pipReturn", arguments: nil)
              },
              onDismissed: { [weak self] in
                self?.pipChannel?.invokeMethod("pipModeChanged", arguments: false)
              }
            )
          }
          result(nil)

        case "clearCallPip":
          if #available(iOS 15.0, *) {
            PipManager.shared.clearCall()
          }
          result(nil)

        case "enterPip":
          if #available(iOS 15.0, *) {
            let args = call.arguments as? [String: Any]
            var connectedDate: Date? = nil
            if let ms = args?["connectedAtMs"] as? Int {
              connectedDate = Date(timeIntervalSince1970: Double(ms) / 1000.0)
            }
            PipManager.shared.startPip(connectedDate: connectedDate)
          }
          result(nil)

        case "exitPip":
          if #available(iOS 15.0, *) {
            PipManager.shared.stop()
          }
          result(nil)

        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // ── Video PiP channel (seeu/video_pip) ─────────────────────────────
      videoPipChannel = FlutterMethodChannel(
        name: "seeu/video_pip",
        binaryMessenger: controller.binaryMessenger
      )
      videoPipChannel?.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(nil); return }
        switch call.method {

        case "setVideoActive":
          // Android-only concept; iOS uses startVideoPip explicitly. No-op here.
          result(nil)

        case "startVideoPip":
          if #available(iOS 15.0, *) {
            let args = call.arguments as? [String: Any]
            let url   = args?["url"]       as? String ?? ""
            let posMs = args?["positionMs"] as? Int   ?? 0
            guard !url.isEmpty else { result(nil); return }

            VideoPipController.shared.onReturn = { [weak self] finalPosMs in
              self?.videoPipChannel?.invokeMethod("videoPipReturn", arguments: finalPosMs)
            }
            VideoPipController.shared.onDismissed = { [weak self] finalPosMs in
              self?.videoPipChannel?.invokeMethod("videoPipStopped", arguments: finalPosMs)
            }
            VideoPipController.shared.start(url: url, positionMs: posMs)
          }
          result(nil)

        case "exitPip":
          if #available(iOS 15.0, *) {
            VideoPipController.shared.stop()
          }
          result(nil)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
