import AVKit
import UIKit

/// Manages video Picture-in-Picture on iOS using AVPlayerLayer.
///
/// Flow:
///   1. Flutter calls `startVideoPip(url, positionMs)` when app goes to background.
///   2. We create a hidden AVPlayer + AVPlayerLayer, seek to position, start PiP.
///   3a. User taps 'Expand' → `restoreUserInterface` → onReturn(posMs) → Flutter navigates back.
///   3b. User taps '×' → `didStop` → onDismissed(posMs) → Flutter shows mini overlay.
@available(iOS 15.0, *)
class VideoPipController: NSObject, AVPictureInPictureControllerDelegate {

  static let shared = VideoPipController()

  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var pipController: AVPictureInPictureController?
  private var containerView: UIView?
  private var didFireReturn = false

  var onReturn: ((Int) -> Void)?       // delivers final positionMs
  var onDismissed: ((Int) -> Void)?    // delivers final positionMs

  private override init() { super.init() }

  // MARK: - Public API

  func start(url: String, positionMs: Int) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    guard let videoUrl = URL(string: url) else { return }

    stop() // clean up any previous session

    let item = AVPlayerItem(url: videoUrl)
    let p = AVPlayer(playerItem: item)
    player = p

    if positionMs > 0 {
      let t = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
      p.seek(to: t) { _ in p.play() }
    } else {
      p.play()
    }

    let layer = AVPlayerLayer(player: p)
    layer.videoGravity = .resizeAspect
    playerLayer = layer

    // The player layer must be in the window hierarchy for PiP to work.
    // We add a 1×1 invisible view so it counts as "on-screen" without
    // disturbing the Flutter UI.
    guard let keyWindow = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow }) else { return }

    let container = UIView(frame: CGRect(x: 0, y: -1, width: 1, height: 1))
    container.clipsToBounds = true
    keyWindow.addSubview(container)
    layer.frame = container.bounds
    container.layer.addSublayer(layer)
    containerView = container

    // init(playerLayer:) returns Optional in Xcode 16 SDK.
    guard let pip = AVPictureInPictureController(playerLayer: layer) else { return }
    pip.delegate = self
    // Class is @available(iOS 15.0, *), so iOS 14.2 check is always true — no need for #available.
    pip.canStartPictureInPictureAutomaticallyFromInline = true
    pipController = pip
    didFireReturn = false

    // Give the layer a moment to receive its first frame, then start PiP.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak pip] in
      guard pip?.isPictureInPicturePossible == true else { return }
      pip?.startPictureInPicture()
    }
  }

  func stop() {
    pipController?.stopPictureInPicture()
    pipController = nil
    player?.pause()
    player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    containerView?.removeFromSuperview()
    containerView = nil
    didFireReturn = false
  }

  // MARK: - Helpers

  private func currentPositionMs() -> Int {
    guard let p = player, p.status == .readyToPlay else { return 0 }
    let secs = CMTimeGetSeconds(p.currentTime())
    return secs.isFinite ? Int(secs * 1000) : 0
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    didFireReturn = true
    onReturn?(currentPositionMs())
    completionHandler(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    let posMs = currentPositionMs()
    let wasExpand = didFireReturn
    stop()
    if !wasExpand {
      onDismissed?(posMs)
    }
  }
}
