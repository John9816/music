import AVFAudio
import AVKit
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  AVRoutePickerViewDelegate
{
  private var castChannel: FlutterMethodChannel?
  private var systemMediaChannel: FlutterMethodChannel?
  private var routePickerView: AVRoutePickerView?
  private var routeObserver: NSObjectProtocol?
  private var remoteCommandTargets: [Any] = []
  private var remoteCommandsConfigured = false
  private var currentArtworkURL: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.751152.duckmusic/cast",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    castChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleCastCall(call, result: result)
    }

    let systemMediaChannel = FlutterMethodChannel(
      name: "com.751152.duckmusic/system_media",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    self.systemMediaChannel = systemMediaChannel
    systemMediaChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleSystemMediaCall(call, result: result)
    }

    if let observer = routeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.notifyRouteState()
    }
  }

  deinit {
    if let observer = routeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    removeRemoteCommandTargets()
  }

  private func handleSystemMediaCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "initialize":
      configureRemoteCommands()
      result(nil)
    case "update":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
        return
      }
      updateSystemMedia(arguments)
      result(nil)
    case "clear":
      clearSystemMedia()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureRemoteCommands() {
    guard !remoteCommandsConfigured else { return }
    remoteCommandsConfigured = true
    let commandCenter = MPRemoteCommandCenter.shared()

    remoteCommandTargets.append(commandCenter.playCommand.addTarget { [weak self] _ in
      self?.systemMediaChannel?.invokeMethod("play", arguments: nil)
      return .success
    })
    remoteCommandTargets.append(commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.systemMediaChannel?.invokeMethod("pause", arguments: nil)
      return .success
    })
    remoteCommandTargets.append(commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.systemMediaChannel?.invokeMethod("previous", arguments: nil)
      return .success
    })
    remoteCommandTargets.append(commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.systemMediaChannel?.invokeMethod("next", arguments: nil)
      return .success
    })
    remoteCommandTargets.append(
      commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
        guard let event = event as? MPChangePlaybackPositionCommandEvent else {
          return .commandFailed
        }
        self?.systemMediaChannel?.invokeMethod(
          "seek",
          arguments: ["positionMs": Int(event.positionTime * 1000)]
        )
        return .success
      }
    )
  }

  private func updateSystemMedia(_ arguments: [String: Any]) {
    configureRemoteCommands()
    let playing = arguments["playing"] as? Bool ?? false
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = !playing
    commandCenter.pauseCommand.isEnabled = playing
    commandCenter.previousTrackCommand.isEnabled = arguments["hasPrevious"] as? Bool ?? false
    commandCenter.nextTrackCommand.isEnabled = arguments["hasNext"] as? Bool ?? false
    commandCenter.changePlaybackPositionCommand.isEnabled = true

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      if playing { try session.setActive(true) }
    } catch {
      NSLog("DuckMusic system media session error: %@", error.localizedDescription)
    }

    let duration = Double(arguments["durationMs"] as? Int ?? 0) / 1000
    let position = Double(arguments["positionMs"] as? Int ?? 0) / 1000
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: arguments["title"] as? String ?? "",
      MPMediaItemPropertyArtist: arguments["artist"] as? String ?? "",
      MPMediaItemPropertyAlbumTitle: arguments["album"] as? String ?? "",
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    if #available(iOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    let artworkURL = arguments["artworkUrl"] as? String
    guard artworkURL != currentArtworkURL else { return }
    currentArtworkURL = artworkURL
    guard let artworkURL, let url = URL(string: artworkURL) else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard
        let self,
        self.currentArtworkURL == artworkURL,
        let data,
        let image = UIImage(data: data)
      else { return }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        guard self.currentArtworkURL == artworkURL else { return }
        var latestInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
        latestInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = latestInfo
      }
    }.resume()
  }

  private func clearSystemMedia() {
    currentArtworkURL = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    if #available(iOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = false
    commandCenter.pauseCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
  }

  private func removeRemoteCommandTargets() {
    let commandCenter = MPRemoteCommandCenter.shared()
    for target in remoteCommandTargets {
      commandCenter.playCommand.removeTarget(target)
      commandCenter.pauseCommand.removeTarget(target)
      commandCenter.previousTrackCommand.removeTarget(target)
      commandCenter.nextTrackCommand.removeTarget(target)
      commandCenter.changePlaybackPositionCommand.removeTarget(target)
    }
    remoteCommandTargets.removeAll()
  }

  private func handleCastCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startCast":
      guard
        let arguments = call.arguments as? [String: Any],
        let rawURL = arguments["url"] as? String,
        let url = URL(string: rawURL),
        url.scheme?.lowercased() == "https",
        url.host != nil
      else {
        result(FlutterError(code: "invalid_url", message: "投屏地址无效", details: nil))
        return
      }
      DispatchQueue.main.async { [weak self] in
        self?.presentRoutePicker(result: result)
      }
    case "stopCast":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentRoutePicker(result: @escaping FlutterResult) {
    guard let viewController = activeViewController() else {
      result(FlutterError(code: "unavailable", message: "无法显示投屏设备列表", details: nil))
      return
    }

    routePickerView?.removeFromSuperview()
    let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
    picker.prioritizesVideoDevices = true
    picker.delegate = self
    picker.alpha = 0.01
    viewController.view.addSubview(picker)
    routePickerView = picker

    guard let button = routeButton(in: picker) else {
      picker.removeFromSuperview()
      routePickerView = nil
      result(FlutterError(code: "unavailable", message: "无法打开投屏设备列表", details: nil))
      return
    }
    button.sendActions(for: .touchUpInside)
    result([
      "supported": true,
      "connected": isAirPlayConnected,
      "pauseLocal": false,
      "message": isAirPlayConnected ? "已连接 AirPlay 设备" : "请选择 AirPlay 设备",
    ])
  }

  func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.notifyRouteState()
      routePickerView.removeFromSuperview()
      if self?.routePickerView === routePickerView {
        self?.routePickerView = nil
      }
    }
  }

  private var isAirPlayConnected: Bool {
    AVAudioSession.sharedInstance().currentRoute.outputs.contains {
      $0.portType == .airPlay
    }
  }

  private func notifyRouteState() {
    let connected = isAirPlayConnected
    castChannel?.invokeMethod(
      "castStateChanged",
      arguments: [
        "connected": connected,
        "pauseLocal": false,
        "message": connected ? "已连接 AirPlay 设备" : "AirPlay 已断开",
      ]
    )
  }

  private func activeViewController() -> UIViewController? {
    let activeScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let activeWindow = activeScene?.windows.first { $0.isKeyWindow }
      ?? activeScene?.windows.first
      ?? window
    var controller = activeWindow?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  private func routeButton(in view: UIView) -> UIButton? {
    if let button = view as? UIButton { return button }
    for subview in view.subviews {
      if let button = routeButton(in: subview) { return button }
    }
    return nil
  }
}
