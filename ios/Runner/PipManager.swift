import AVKit
import UIKit

/// Управляет системным PiP-окном для звонков на iOS 15+.
///
/// Жизненный цикл:
///   1. Flutter вызывает `prepareCall` при открытии экрана звонка — регистрируем
///      lifecycle-наблюдатели.
///   2. Нажатие «Свернуть» во Flutter → `enterPip` channel → `startPip()` — запускаем
///      PiP немедленно в foreground (плавает поверх приложения).
///   3. Уход в фон (`willResignActive`) → запускаем PiP если ещё не запущен.
///   4. Возврат в приложение (`didBecomeActive`) → останавливаем PiP.
///   5. Пользователь нажал «Развернуть» в PiP → `restoreUserInterface` delegate →
///      `onReturn` → Flutter восстанавливает полноэкранный звонок.
///   6. Пользователь нажал «×» или PiP закрылся иначе → `didStop` → тот же
///      `onReturn` → звонок не теряется.
///   7. Завершение звонка → Flutter вызывает `clearCall` → снимаем наблюдатели.
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
    // Nil out callbacks BEFORE stop() to prevent async delegate from firing them
    // after the call has already ended.
    onReturn    = nil
    onDismissed = nil
    stop()
    callAvatarUrl = nil
    callUsername  = ""
    callKind      = "voice"
  }

  /// Запустить нативный PiP вручную (при нажатии «Свернуть» внутри приложения).
  /// - Parameter connectedDate: момент соединения звонка — таймер покажет реальную длительность.
  ///   Если nil — таймер стартует с 0 (для голосовых каналов где нет точного времени).
  /// Идемпотент: если PiP уже запущен — ничего не делает.
  func startPip(connectedDate: Date? = nil) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    guard pipController == nil else { return }
    _startPip(connectedDate: connectedDate)
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
    // PiP запущен — останавливаем. Если это возврат через «Развернуть»,
    // система уже вызвала restoreUserInterface до didBecomeActive.
    // Если возврат иным путём — didStopPictureInPicture вызовет onReturn.
    pipController?.stopPictureInPicture()
  }

  // MARK: - Internal PiP start

  private func _startPip(connectedDate: Date? = nil) {
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

    // Используем реальное время начала звонка (если передано) — таймер показывает
    // корректную длительность даже если minimize нажат на 5-й минуте.
    startDate = connectedDate ?? Date()
    startDisplayLink()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak pip] in
      guard pip?.isPictureInPicturePossible == true else { return }
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
          guard let container = avatarContainer else { return }
          iconView?.removeFromSuperview()
          let imgView = UIImageView(image: img)
          imgView.contentMode = .scaleAspectFill
          imgView.translatesAutoresizingMaskIntoConstraints = false
          container.addSubview(imgView)
          NSLayoutConstraint.activate([
            imgView.topAnchor.constraint(equalTo: container.topAnchor),
            imgView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imgView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imgView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
          ])
        }
      }.resume()
    }
  }

  // MARK: - Timer

  private func startDisplayLink() {
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 1, preferred: 1)
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

  /// Пользователь нажал «Развернуть» → помечаем флаг и уведомляем Flutter.
  /// Вызывается ДО didStopPictureInPicture.
  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    returnCallbackFired = true
    onReturn?()
    completionHandler(true)
  }

  /// PiP остановлен — независимо от причины (Expand, ×, программно, система).
  /// Сюда приходят ВСЕ случаи завершения PiP. Обнуляем состояние и при необходимости
  /// восстанавливаем экран звонка (если закрыт не через Expand).
  func pictureInPictureControllerDidStopPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    let wasExpand = returnCallbackFired
    // Обнуляем pipController — предотвращаем повторный stopPictureInPicture
    // из appDidBecomeActive (уже обработан здесь).
    pipController  = nil
    pipVC          = nil
    timerLabel     = nil
    startDate      = nil
    stopDisplayLink()
    returnCallbackFired = false
    onDismissed?()
    if !wasExpand {
      // PiP закрыт через «×», системно или при возврате без Expand →
      // восстанавливаем полноэкранный звонок, чтобы звонок не завис «в воздухе».
      onReturn?()
    }
  }
}
