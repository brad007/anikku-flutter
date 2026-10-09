import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var routePickerView: AVRoutePickerView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let castChannel = FlutterMethodChannel(
      name: "app.anikku/cast",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    castChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "showAirPlayPicker" {
        self?.showAirPlayPicker(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let windowChannel = FlutterMethodChannel(
      name: "app.anikku/window",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    windowChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "enterFullscreen", "exitFullscreen":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func showAirPlayPicker(result: @escaping FlutterResult) {
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow }),
      let rootView = window.rootViewController?.view else {
      result(FlutterError(code: "no_window", message: "The window is not ready.", details: nil))
      return
    }
    let picker = routePickerView ?? AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
    picker.prioritizesVideoDevices = true
    picker.tintColor = UIColor.white
    picker.activeTintColor = UIColor.systemRed
    if picker.superview == nil {
      picker.center = CGPoint(x: rootView.bounds.midX, y: rootView.bounds.midY)
      rootView.addSubview(picker)
    }
    routePickerView = picker
    DispatchQueue.main.async {
      if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
        button.sendActions(for: .touchUpInside)
        result(nil)
      } else {
        result(FlutterError(code: "route_picker_unavailable", message: "AirPlay picker is unavailable.", details: nil))
      }
    }
  }
}
