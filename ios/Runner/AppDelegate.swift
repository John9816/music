import AVFAudio
import AVKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  AVRoutePickerViewDelegate
{
  private var castChannel: FlutterMethodChannel?
  private var routePickerView: AVRoutePickerView?
  private var routeObserver: NSObjectProtocol?

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
