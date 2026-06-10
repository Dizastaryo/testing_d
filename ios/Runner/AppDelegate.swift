import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var pipChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
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
          // iOS: запустить нативный PiP немедленно (например при нажатии «Свернуть»).
          if #available(iOS 15.0, *) {
            PipManager.shared.startPip()
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
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
