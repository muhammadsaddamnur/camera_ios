import Flutter
import UIKit
import AVFoundation

public class IosCameraProPlugin: NSObject, FlutterPlugin {

    private let cameraManager = CameraManager()
    private var eventSink: FlutterEventSink?

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "ios_camera_pro",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "ios_camera_pro/events",
            binaryMessenger: registrar.messenger()
        )

        let instance = IosCameraProPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)

        let factory = CameraPreviewFactory(cameraManager: instance.cameraManager)
        registrar.register(factory, withId: "ios_camera_pro/preview")
    }

    // MARK: - Method Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {

        // ── Kamera tersedia ────────────────────────────────────────
        case "getAvailableCameras":
            cameraManager.getAvailableCameras(result: result)

        // ── Inisialisasi ───────────────────────────────────────────
        case "initialize":
            handleInitialize(args: args, result: result)

        case "dispose":
            cameraManager.dispose()
            result(nil)

        // ── Anti-macro ─────────────────────────────────────────────
        case "setAntiMacroEnabled":
            let enabled = args["enabled"] as? Bool ?? false
            cameraManager.setAntiMacroEnabled(enabled, result: result)

        // ── Flash & Torch ──────────────────────────────────────────
        case "setFlashMode":
            let mode = args["mode"] as? String ?? "off"
            cameraManager.setFlashMode(mode, result: result)

        case "setTorchMode":
            let enabled = args["enabled"] as? Bool ?? false
            let level = (args["level"] as? NSNumber)?.floatValue ?? 1.0
            cameraManager.setTorchMode(enabled, level: level, result: result)

        // ── Zoom ───────────────────────────────────────────────────
        case "setZoomLevel":
            let zoom = (args["zoom"] as? NSNumber)?.doubleValue ?? 1.0
            cameraManager.setZoomLevel(CGFloat(zoom), result: result)

        case "getZoomRange":
            cameraManager.getZoomRange(result: result)

        // ── Focus ──────────────────────────────────────────────────
        case "setFocusPoint":
            let x = (args["x"] as? NSNumber)?.doubleValue ?? 0.5
            let y = (args["y"] as? NSNumber)?.doubleValue ?? 0.5
            cameraManager.setFocusPoint(x: x, y: y, result: result)

        // ── Exposure ───────────────────────────────────────────────
        case "setExposurePoint":
            let x = (args["x"] as? NSNumber)?.doubleValue ?? 0.5
            let y = (args["y"] as? NSNumber)?.doubleValue ?? 0.5
            cameraManager.setExposurePoint(x: x, y: y, result: result)

        case "setExposureCompensation":
            let ev = (args["ev"] as? NSNumber)?.floatValue ?? 0.0
            cameraManager.setExposureCompensation(ev, result: result)

        // ── Ganti kamera ───────────────────────────────────────────
        case "switchCamera":
            cameraManager.switchCamera(result: result)

        case "switchToCamera":
            let cameraId = args["cameraId"] as? String ?? ""
            cameraManager.switchToCamera(cameraId: cameraId, result: result)

        // ── Foto & Video ───────────────────────────────────────────
        case "takePicture":
            cameraManager.takePicture(result: result)

        case "startVideoRecording":
            cameraManager.startVideoRecording(result: result)

        case "stopVideoRecording":
            cameraManager.stopVideoRecording(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleInitialize(args: [String: Any], result: @escaping FlutterResult) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            doInitialize(args: args, result: result)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.doInitialize(args: args, result: result)
                    } else {
                        result(FlutterError(code: "PERMISSION_DENIED", message: "Izin kamera ditolak", details: nil))
                    }
                }
            }

        case .denied, .restricted:
            result(FlutterError(code: "PERMISSION_DENIED", message: "Izin kamera tidak tersedia. Buka Settings.", details: nil))

        @unknown default:
            result(FlutterError(code: "UNKNOWN", message: "Status izin tidak diketahui", details: nil))
        }
    }

    private func doInitialize(args: [String: Any], result: @escaping FlutterResult) {
        let lensDirection   = args["lensDirection"] as? String ?? "back"
        let cameraId        = args["cameraId"] as? String          // optional, dari CameraDescription.uniqueId
        let resolution      = args["resolution"] as? String ?? "high"
        let enableAntiMacro = args["enableAntiMacro"] as? Bool ?? false

        cameraManager.setEventSink(eventSink)
        cameraManager.initialize(
            cameraPosition: lensDirection,
            cameraId: cameraId,
            resolution: resolution,
            enableAntiMacro: enableAntiMacro,
            result: result
        )
    }
}

// MARK: - FlutterStreamHandler

extension IosCameraProPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        cameraManager.setEventSink(events)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        cameraManager.setEventSink(nil)
        return nil
    }
}
