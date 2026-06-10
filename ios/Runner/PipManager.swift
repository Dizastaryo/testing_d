import AVKit
import UIKit

/// Управляет системным PiP-окном для звонков на iOS 15+.
///
/// Логика: PiP НЕ запускается вручную при нажатии «свернуть».
/// Вместо этого регистрируются lifecycle-наблюдатели:
///   - willResignActive → PiP стартует (когда приложение уходит в фон)
///   - didBecomeActive  → PiP гасится (когда приложение возвращается)
/// Внутри приложения видит только Flutter mini overlay.
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

  // Сохранённые данные звонка для авто-запуска PiP при уходе в фон.
  private var callAvatarUrl: String?
  private var callUsername: String = ""
  private var callKind: String = "voice"

  /// true если onReturn уже был вызван делегатом (Expand) — чтобы appDidBecomeActive
  /// не вызвал его повторно.
  private var returnCallbackFired = false

  private override init() { super.init() }

  // MARK: - Public API

  /// Подготовить PiP: сохранить данные звонка и зарегистрировать lifecycle-наблюдатели.
  /// Вызывается когда экран звонка открывается (initState во Flutter).
  /// PiP запустится автоматически при уходе приложения в фон.
  func prepareCall(
    avatarUrl: String?,
    username: String,
    kind: String,
    onReturn: @escaping () -> Void,
    onDismissed: @escaping () -> Void
  ) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    callAvatarUrl  = avatarUrl
    callUsername   = username
    callKind       = kind
    self.onReturn  = onReturn
    self.onDismissed = onDismissed
    // Переподписываемся (идемпотентно).
    NotificationCenter.default.removeObserver(self,
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.removeObserver(self,
      name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self,
      selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  /// Полная очистка: остановить PiP + снять наблюдатели. Вызывается при завершении звонка.
  func clearCall() {
    NotificationCenter.default.removeObserver(self,
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.removeObserver(self,
      name: UIApplication.didBecomeActiveNotification, object: nil)
    stop()
    callAvatarUrl = nil
    callUsername  = ""
    callKind      = "voice"
    onReturn      = nil
    onDismissed   = nil
  }

  /// Запустить нативный PiP вручную (при нажатии «Свернуть» внутри приложения).
  /// Идемпотент: если PiP уже запущен — ничего не делает.
  func startPip() {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    guard pipController == nil else { return }
    _startPip()
  }

  /// Остановить PiP-окно (не снимает lifecycle-наблюдатели — используется при
  /// возврате в приложение, чтобы следующий уход в фон снова запустил PiP).
  func stop() {
    returnCallbackFired = false
    stopDisplayLink()
    pipController?.stopPictureInPicture()
    pipController  = nil
    pipVC          = nil
    timerLabel     = nil
    startDate      = nil
  }

  // MARK: - Lifecycle observers

  @objc private func appWillResignActive() {
    guard pipController == nil else { return }  // уже в PiP
    _startPip()
  }

  @objc private func appDidBecomeActive() {
    guard pipController != nil else { return }
    let alreadyReturned = returnCallbackFired
    stop()  // сбрасывает returnCallbackFired
    if !alreadyReturned {
      // PiP закрылся не через Expand (свайп, системное закрытие) → восстанавливаем экран звонка
      onReturn?()
    }
  }

  // MARK: - Internal PiP start

  private func _startPip() {
    stop()  // сброс предыдущего состояния

    let vc = AVPictureInPictureVideoCallViewController()
    vc.preferredContentSize = CGSize(width: 160, height: 240)
    pipVC = vc

    buildContentView(in: vc.view, avatarUrl: callAvatarUrl,
                     username: callUsername, kind: callKind)

    // Не фильтруем по foregroundActive: при willResignActive сцена уже
    // переходит в foregroundInactive, поэтому фильтр вернёт пустой массив.
    let keyWindow = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
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

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak pip] in
      pip?.startPictureInPicture()
    }
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
    if #available(iOS 15.0, *) {
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 1, preferred: 1)
    } else {
      link.preferredFramesPerSecond = 1
    }
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
    returnCallbackFired = true
    onReturn?()
    completionHandler(true)
  }
}
