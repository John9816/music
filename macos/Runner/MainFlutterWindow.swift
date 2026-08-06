import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var lyricStatusItem: NSStatusItem?

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
