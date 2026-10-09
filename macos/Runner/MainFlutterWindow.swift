import Cocoa
import FlutterMacOS
import AVKit

class MainFlutterWindow: NSWindow {
  private var routePickerView: AVRoutePickerView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(origin: windowFrame.origin, size: NSSize(width: 1280, height: 800)), display: true)
    self.minSize = NSSize(width: 800, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let castChannel = FlutterMethodChannel(
      name: "app.anikku/cast",
      binaryMessenger: flutterViewController.engine.binaryMessenger
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
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enterFullscreen":
        self?.setFullscreen(true, result: result)
      case "exitFullscreen":
        self?.setFullscreen(false, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func setFullscreen(_ enabled: Bool, result: @escaping FlutterResult) {
    let active = styleMask.contains(.fullScreen)
    if enabled != active {
      toggleFullScreen(nil)
    }
    result(nil)
  }

  private func showAirPlayPicker(result: @escaping FlutterResult) {
    guard let contentView = contentView else {
      result(FlutterError(code: "no_window", message: "The window is not ready.", details: nil))
      return
    }
    let picker = routePickerView ?? AVRoutePickerView(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
    if picker.superview == nil {
      picker.frame = NSRect(
        x: contentView.bounds.maxX - 64,
        y: contentView.bounds.maxY - 64,
        width: 44,
        height: 44
      )
      contentView.addSubview(picker)
    }
    routePickerView = picker
    DispatchQueue.main.async {
      if let button = picker.subviews.compactMap({ $0 as? NSButton }).first {
        button.performClick(nil)
        result(nil)
      } else {
        result(FlutterError(code: "route_picker_unavailable", message: "AirPlay picker is unavailable.", details: nil))
      }
    }
  }
}
