import Cocoa
import FlutterMacOS
import AVKit
import MediaPlayer

class MainFlutterWindow: NSWindow, AVRoutePickerViewDelegate {
  private var lyricStatusItem: NSStatusItem?
  private var castChannel: FlutterMethodChannel?
  private var castPlayer: AVPlayer?
  private var castRoutePicker: AVRoutePickerView?
  private var castRouteObservation: NSKeyValueObservation?
  private var systemMediaChannel: FlutterMethodChannel?
  private var remoteCommandTargets: [Any] = []
  private var remoteCommandsConfigured = false
  private var currentArtworkURL: String?
  private var currentArtwork: MPMediaItemArtwork?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // 保留标准红绿灯，隐藏标题栏文字，让按钮悬浮在深色内容上（fullSizeContentView）
    styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    title = ""
    // Flutter 的全部控件都绘制在同一个 NSView 中。开启整窗背景拖动会让
    // NSWindow 抢先处理轻微移动的点击，导致部分 Flutter 按钮收不到事件。
    isMovableByWindowBackground = false
    isOpaque = false
    appearance = NSAppearance(named: .darkAqua)
    // 与 Flutter 内容区的森林绿底色一致，避免标题栏或启动阶段闪白。
    backgroundColor = NSColor(
      srgbRed: 13.0 / 255.0, green: 33.0 / 255.0, blue: 22.0 / 255.0, alpha: 1.0)
    hasShadow = true
    minSize = NSSize(width: 840, height: 600)
    setContentSize(NSSize(width: 1280, height: 800))
    center()

    // 窗口拖动通道：Flutter 顶部预留区拖动时按增量移动窗口
    let registrar = flutterViewController.registrar(forPlugin: "DuckMusicWindow")
    let channel = FlutterMethodChannel(
      name: "duckmusic/window", binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "moveBy",
        let args = call.arguments as? [String: Double]
      {
        var frame = self.frame
        frame.origin.x += args["dx"] ?? 0
        frame.origin.y -= args["dy"] ?? 0
        self.setFrame(frame, display: false)
        result(nil)
      } else if call.method == "toggleVisibility" {
        if self.isVisible && NSApp.isActive {
          self.orderOut(nil)
        } else {
          self.showMainWindow()
        }
        result(nil)
      } else if call.method == "showWindow" {
        self.showMainWindow()
        result(nil)
      } else if call.method == "setStatusLyrics",
        let args = call.arguments as? [String: Any]
      {
        let enabled = args["enabled"] as? Bool ?? false
        let text = args["text"] as? String ?? ""
        self.updateStatusLyrics(enabled: enabled, text: text)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let castRegistrar = flutterViewController.registrar(forPlugin: "DuckMusicCast")
    let castChannel = FlutterMethodChannel(
      name: "com.751152.duckmusic/cast", binaryMessenger: castRegistrar.messenger)
    self.castChannel = castChannel
    castChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleCastCall(call, result: result)
    }

    // 系统媒体卡：与 iOS 端共用同一套通道协议（见 ios/Runner/AppDelegate.swift），
    // 让 macOS 也能在「正在播放」控制中心与媒体键上控制播放。
    let systemMediaRegistrar = flutterViewController.registrar(
      forPlugin: "DuckMusicSystemMedia")
    let systemMediaChannel = FlutterMethodChannel(
      name: "com.751152.duckmusic/system_media",
      binaryMessenger: systemMediaRegistrar.messenger)
    self.systemMediaChannel = systemMediaChannel
    systemMediaChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleSystemMediaCall(call, result: result)
    }

  }

  deinit {
    removeRemoteCommandTargets()
  }

  // MARK: - 系统媒体卡（MPNowPlayingInfoCenter / MPRemoteCommandCenter）

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

    // macOS 没有 AVAudioSession，无需配置音频会话。

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
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused

    let artworkURL = arguments["artworkUrl"] as? String
    if artworkURL == currentArtworkURL, let currentArtwork {
      info[MPMediaItemPropertyArtwork] = currentArtwork
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      return
    }
    currentArtworkURL = artworkURL
    currentArtwork = nil
    guard let artworkURL, let url = URL(string: artworkURL) else { return }
    var artworkRequest = URLRequest(url: url)
    let artworkHost = url.host?.lowercased()
    if artworkHost == "music.126.net" || artworkHost?.hasSuffix(".music.126.net") == true {
      artworkRequest.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
      artworkRequest.setValue(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
        forHTTPHeaderField: "User-Agent"
      )
    }
    URLSession.shared.dataTask(with: artworkRequest) { [weak self] data, response, _ in
      guard
        let self,
        self.currentArtworkURL == artworkURL,
        let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode),
        let data,
        let image = NSImage(data: data)
      else {
        DispatchQueue.main.async {
          if self?.currentArtworkURL == artworkURL {
            self?.currentArtworkURL = nil
          }
        }
        return
      }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        guard self.currentArtworkURL == artworkURL else { return }
        self.currentArtwork = artwork
        var latestInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
        latestInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = latestInfo
      }
    }.resume()
  }

  private func clearSystemMedia() {
    currentArtworkURL = nil
    currentArtwork = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
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
      presentCastPicker(url: url, result: result)
    case "stopCast":
      resetCastPlayer(notify: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentCastPicker(url: URL, result: @escaping FlutterResult) {
    resetCastPlayer(notify: false)
    let player = AVPlayer(url: url)
    player.allowsExternalPlayback = true
    let picker = AVRoutePickerView(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
    picker.player = player
    picker.delegate = self
    picker.alphaValue = 0.01
    picker.isRoutePickerButtonBordered = false
    contentView?.addSubview(picker)
    picker.layoutSubtreeIfNeeded()

    castPlayer = player
    castRoutePicker = picker
    castRouteObservation = player.observe(
      \.isExternalPlaybackActive,
      options: [.new]
    ) { [weak self] observedPlayer, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if observedPlayer.isExternalPlaybackActive {
          observedPlayer.play()
          self.notifyCastState(connected: true)
        } else {
          observedPlayer.pause()
          self.notifyCastState(connected: false)
        }
      }
    }

    guard let button = routeButton(in: picker) else {
      resetCastPlayer(notify: false)
      result(FlutterError(code: "unavailable", message: "无法打开投屏设备列表", details: nil))
      return
    }
    button.performClick(nil)
    result([
      "supported": true,
      "connected": player.isExternalPlaybackActive,
      "pauseLocal": player.isExternalPlaybackActive,
      "message": player.isExternalPlaybackActive ? "已连接 AirPlay 设备" : "请选择 AirPlay 设备",
    ])
  }

  func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self = self, let player = self.castPlayer else { return }
      if player.isExternalPlaybackActive {
        player.play()
        self.notifyCastState(connected: true)
      } else {
        player.pause()
        self.notifyCastState(connected: false)
      }
    }
  }

  private func notifyCastState(connected: Bool) {
    castChannel?.invokeMethod(
      "castStateChanged",
      arguments: [
        "connected": connected,
        "pauseLocal": connected,
        "message": connected ? "已连接 AirPlay 设备" : "AirPlay 已断开",
      ]
    )
  }

  private func resetCastPlayer(notify: Bool) {
    castRouteObservation?.invalidate()
    castRouteObservation = nil
    castPlayer?.pause()
    castPlayer?.replaceCurrentItem(with: nil)
    castPlayer = nil
    castRoutePicker?.removeFromSuperview()
    castRoutePicker = nil
    if notify { notifyCastState(connected: false) }
  }

  private func routeButton(in view: NSView) -> NSButton? {
    if let button = view as? NSButton { return button }
    for subview in view.subviews {
      if let button = routeButton(in: subview) { return button }
    }
    return nil
  }

  private func showMainWindow() {
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func updateStatusLyrics(enabled: Bool, text: String) {
    if !enabled {
      if let item = lyricStatusItem {
        NSStatusBar.system.removeStatusItem(item)
      }
      lyricStatusItem = nil
      return
    }

    if lyricStatusItem == nil {
      lyricStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      lyricStatusItem?.button?.toolTip = "柒伍壹壹音乐状态栏歌词"
      lyricStatusItem?.button?.target = self
      lyricStatusItem?.button?.action = #selector(statusItemClicked)
    }
    lyricStatusItem?.button?.title = text.isEmpty ? "柒伍壹壹音乐" : text
  }

  @objc private func statusItemClicked() {
    showMainWindow()
  }
}
