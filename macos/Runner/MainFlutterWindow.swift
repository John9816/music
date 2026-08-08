import Cocoa
import FlutterMacOS
import AVKit

class MainFlutterWindow: NSWindow, AVRoutePickerViewDelegate {
  private var lyricStatusItem: NSStatusItem?
  private var castChannel: FlutterMethodChannel?
  private var castPlayer: AVPlayer?
  private var castRoutePicker: AVRoutePickerView?
  private var castRouteObservation: NSKeyValueObservation?

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
    minSize = NSSize(width: 800, height: 600)
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
