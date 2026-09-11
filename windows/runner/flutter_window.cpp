#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupWindowChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ShowAndActivate() {
  HWND handle = GetHandle();
  if (!handle) {
    return;
  }
  if (IsIconic(handle)) {
    ShowWindow(handle, SW_RESTORE);
  } else {
    ShowWindow(handle, SW_SHOW);
  }
  SetForegroundWindow(handle);
}

void FlutterWindow::SetupWindowChannel() {
  window_registrar_ = std::make_unique<flutter::PluginRegistrarWindows>(
      flutter_controller_->engine()->GetRegistrarForPlugin("DuckMusicWindow"));
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          window_registrar_->messenger(), "duckmusic/window",
          &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        HWND handle = GetHandle();

        if (method == "moveBy") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args || !handle) {
            result->Success();
            return;
          }
          double dx = 0;
          double dy = 0;
          auto dx_it = args->find(flutter::EncodableValue("dx"));
          if (dx_it != args->end()) {
            if (const auto* value = std::get_if<double>(&dx_it->second)) {
              dx = *value;
            }
          }
          auto dy_it = args->find(flutter::EncodableValue("dy"));
          if (dy_it != args->end()) {
            if (const auto* value = std::get_if<double>(&dy_it->second)) {
              dy = *value;
            }
          }
          RECT rect;
          if (GetWindowRect(handle, &rect)) {
            // macOS 用 AppKit 的 Y 轴向上坐标系，所以那边是 origin.y -= dy；
            // Win32 的 Y 轴向下，直接相加即可。
            SetWindowPos(handle, nullptr,
                         rect.left + static_cast<int>(dx),
                         rect.top + static_cast<int>(dy), 0, 0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
          }
          result->Success();
        } else if (method == "toggleVisibility") {
          if (handle) {
            // 与 macOS 一致：仅当窗口可见且处于前台时才隐藏，否则唤到前台。
            bool visible = IsWindowVisible(handle) && !IsIconic(handle);
            bool foreground = GetForegroundWindow() == handle;
            if (visible && foreground) {
              ShowWindow(handle, SW_HIDE);
            } else {
              ShowAndActivate();
            }
          }
          result->Success();
        } else if (method == "showWindow") {
          ShowAndActivate();
          result->Success();
        } else if (method == "setStatusLyrics") {
          // Windows 没有 macOS 状态栏（NSStatusItem）那样的常驻歌词位置，
          // 这里返回成功的空实现，避免 Dart 侧因 notImplemented 抛异常。
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  window_registrar_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
