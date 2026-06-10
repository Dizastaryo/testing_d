import AVKit
import UIKit

/// Управляет системным PiP-окном для звонков на iOS 15+.
/// Показывает аватар собеседника + имя + таймер в нативном PiP-окне.
@available(iOS 15.0, *)
class PipManager: NSObject, AVPictureInPictureControllerDelegate {

  static let shared = PipManager()

  private var pipController: AVPictureInPictureController?
  private var pipVC: AVPictureInPictureVideoCallViewController?
  private var displayLink: CADisplayLink?
  private var startDate: Date?
  private var timerLabel: UILabel?
  private var onReturn: (() -> Void)?
  private var onDismissed: (() -> Void)?

  private override init() { super.init() }

  // MARK: - Public API

  func start(
    avatarUrl: String?,
    username: String,
    kind: String,
    onReturn: @escaping () -> Void,
    onDismissed: @escaping () -> Void
  ) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    self.onReturn   = onReturn
    self.onDismissed = onDismissed
    stop()

    let vc = AVPictureInPictureVideoCallViewController()
    vc.preferredContentSize = CGSize(width: 160, height: 240)
    pipVC = vc

    buildContentView(in: vc.view, avatarUrl: avatarUrl, username: username, kind: kind)

    // UIApplication.shared.windows deprecated on iOS 16+ (returns empty array).
    // Use connectedScenes instead to reliably get the key window.
    let keyWindow = UIApplication.shared.connectedScenes
        .filter { $0.activationState == .foregroundActive }
        .compactMap { $0 as? UIWindowScene }
        .first?
        .windows
        .first(where: { $0.isKeyWindow })
        ?? UIApplication.shared.delegate?.window.flatMap { $0 }
    guard let sourceView = keyWindow?.rootViewController?.view else { return }

    let contentSource = AVPictureInPictureController.ContentSource(
      activeVideoCallSourceView: sourceView,
      contentViewController: vc
    )
    let pip = AVPictureInPictureController(contentSource: contentSource)
    pip.delegate = self
    pipController = pip

    startDate = Date()
    startDisplayLink()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak pip] in
      pip?.startPictureInPicture()
    }
  }

  func stop() {
    stopDisplayLink()
    pipController?.stopPictureInPicture()
    pipController  = nil
    pipVC          = nil
    timerLabel     = nil
    startDate      = nil
  }

  // MARK: - Content view

  private func buildContentView(in view: UIView, avatarUrl: String?, username: String, kind: String) {
    view.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.18, alpha: 1)

    let avatarSize: CGFloat = 72
    let accent = UIColor(red: 1, green: 0.35, blue: 0.24, alpha: 1) // #FF5A3C

    // ── Аватар-контейнер ──────────────────────────────────────────────────
    let avatarContainer = UIView()
    avatarContainer.translatesAutoresizingMaskIntoConstraints = false
    avatarContainer.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    avatarContainer.layer.cornerRadius = avatarSize / 2
    avatarContainer.clipsToBounds = true
    view.addSubview(avatarContainer)

    // Иконка типа звонка (fallback, пока не загрузится аватар)
    let sysName = kind == "video" ? "video.fill" : "phone.fill"
    let iconView = UIImageView(image: UIImage(systemName: sysName))
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.tintColor = accent
    iconView.contentMode = .scaleAspectFit
    avatarContainer.addSubview(iconView)

    // ── Имя пользователя ──────────────────────────────────────────────────
    let nameLabel = UILabel()
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.text = username.isEmpty ? "Звонок" : "@\(username)"
    nameLabel.textColor = .white
    nameLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
    nameLabel.textAlignment = .center
    view.addSubview(nameLabel)

    // ── Таймер ────────────────────────────────────────────────────────────
    let timer = UILabel()
    timer.translatesAutoresizingMaskIntoConstraints = false
    timer.text = "00:00"
    timer.textColor = UIColor.white.withAlphaComponent(0.55)
    timer.font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    timer.textAlignment = .center
    view.addSubview(timer)
    timerLabel = timer

    NSLayoutConstraint.activate([
      avatarContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      avatarContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
      avatarContainer.widthAnchor.constraint(equalToConstant: avatarSize),
      avatarContainer.heightAnchor.constraint(equalToConstant: avatarSize),

      iconView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 28),
      iconView.heightAnchor.constraint(equalToConstant: 28),

      nameLabel.topAnchor.constraint(equalTo: avatarContainer.bottomAnchor, constant: 10),
      nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

      timer.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
      timer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    ])

    // ── Загрузка аватара ──────────────────────────────────────────────────
    if let urlStr = avatarUrl, let url = URL(string: urlStr) {
      URLSession.shared.dataTask(with: url) { data, _, _ in
        guard let data = data, let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak avatarContainer, weak iconView] in
          iconView?.removeFromSuperview()
          let imgView = UIImageView(image: img)
          imgView.contentMode = .scaleAspectFill
          imgView.frame = avatarContainer?.bounds ?? .zero
          imgView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          avatarContainer?.addSubview(imgView)
        }
      }.resume()
    }
  }

  // MARK: - Timer

  private func startDisplayLink() {
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.preferredFramesPerSecond = 1
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
  }

  @objc private func tick() {
    guard let start = startDate else { return }
    let elapsed = Int(Date().timeIntervalSince(start))
    let m = elapsed / 60
    let s = elapsed % 60
    timerLabel?.text = String(format: "%02d:%02d", m, s)
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStopPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    stopDisplayLink()
    onDismissed?()
  }

  /// Пользователь нажал «Развернуть» → возвращаем в приложение.
  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    onReturn?()
    completionHandler(true)
  }
}
