import AVFoundation
import Flutter
import UIKit

// MARK: - CameraManager

class CameraManager: NSObject {

    // MARK: - Properties

    private(set) var session: AVCaptureSession?
    private var currentDevice: AVCaptureDevice?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureMovieFileOutput?

    private var eventSink: FlutterEventSink?
    private var pendingPhotoResult: FlutterResult?

    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var currentFlashMode: AVCaptureDevice.FlashMode = .off
    private var isRecordingVideo = false

    // MARK: - Public API

    func setEventSink(_ sink: FlutterEventSink?) {
        eventSink = sink
    }

    // MARK: - Available Cameras

    /// Kembalikan daftar semua kamera yang tersedia di perangkat (mirip `availableCameras()` Flutter).
    func getAvailableCameras(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let cameras = CameraManager.discoverAllCameras()
            DispatchQueue.main.async { result(cameras) }
        }
    }

    static func discoverAllCameras() -> [[String: Any]] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera,
        ]
        if #available(iOS 13.0, *) {
            deviceTypes += [
                .builtInUltraWideCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
            ]
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.map { device in
            [
                "name": device.localizedName,
                "uniqueId": device.uniqueID,
                "lensDirection": positionString(device.position),
                "sensorOrientation": sensorOrientation(for: device),
                "hasFlash": device.hasFlash,
                "hasTorch": device.hasTorch,
                "deviceType": deviceTypeString(device.deviceType),
                "aspectRatios": availableAspectRatios(for: device),
            ]
        }
    }

    // MARK: - Available Cameras Helpers (static)

    private static func positionString(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: return "front"
        case .back:  return "back"
        default:     return "external"
        }
    }

    private static func sensorOrientation(for device: AVCaptureDevice) -> Int {
        // Sensor kamera iOS selalu landscape.
        // Back = 90 derajat, Front = 270 derajat (mirrored)
        return device.position == .front ? 270 : 90
    }

    private static func deviceTypeString(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInWideAngleCamera: return "wideAngle"
        case .builtInTelephotoCamera: return "telephoto"
        case .builtInTrueDepthCamera: return "trueDepth"
        default:
            if #available(iOS 13.0, *) {
                switch type {
                case .builtInUltraWideCamera: return "ultraWide"
                case .builtInDualCamera:      return "dual"
                case .builtInDualWideCamera:  return "dualWide"
                case .builtInTripleCamera:    return "triple"
                default: break
                }
            }
            return "unknown"
        }
    }

    /// Kumpulkan aspect ratio unik dari semua format yang didukung kamera.
    private static func availableAspectRatios(for device: AVCaptureDevice) -> [[String: Int]] {
        var seen = Set<String>()
        var ratios: [[String: Int]] = []

        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.height > 0 else { continue }
            let g = gcd(Int(dims.width), Int(dims.height))
            let w = Int(dims.width) / g
            let h = Int(dims.height) / g
            let key = "\(w):\(h)"
            if seen.insert(key).inserted {
                ratios.append(["width": w, "height": h])
            }
        }
        return ratios
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    // MARK: - Initialize

    func initialize(
        cameraPosition: String,
        cameraId: String?,
        resolution: String,
        enableAntiMacro: Bool,
        result: @escaping FlutterResult
    ) {
        let position: AVCaptureDevice.Position = cameraPosition == "front" ? .front : .back
        let preset = mapResolutionPreset(resolution)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupSession(
                cameraId: cameraId,
                position: position,
                preset: preset,
                enableAntiMacro: enableAntiMacro,
                result: result
            )
        }
    }

    private func setupSession(
        cameraId: String?,
        position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset,
        enableAntiMacro: Bool,
        result: @escaping FlutterResult
    ) {
        let newSession = AVCaptureSession()
        newSession.beginConfiguration()
        newSession.sessionPreset = preset

        guard let device = getDevice(cameraId: cameraId, position: position) else {
            DispatchQueue.main.async {
                result(FlutterError(
                    code: "CAMERA_ERROR",
                    message: "Perangkat kamera tidak ditemukan",
                    details: nil
                ))
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard newSession.canAddInput(input) else {
                throw NSError(
                    domain: "CameraError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Tidak dapat menambahkan input kamera"]
                )
            }
            newSession.addInput(input)

            let photoOut = AVCapturePhotoOutput()
            if newSession.canAddOutput(photoOut) { newSession.addOutput(photoOut) }

            let videoOut = AVCaptureMovieFileOutput()
            if newSession.canAddOutput(videoOut) { newSession.addOutput(videoOut) }

            newSession.commitConfiguration()

            session = newSession
            currentDevice = device
            photoOutput = photoOut
            videoOutput = videoOut
            currentCameraPosition = position

            newSession.startRunning()

            if enableAntiMacro { setupAntiMacro(device: device) }

            DispatchQueue.main.async { [weak self] in
                result(nil)
                self?.sendEvent(["event": "cameraInitialized"])
            }

        } catch {
            newSession.commitConfiguration()
            DispatchQueue.main.async {
                result(FlutterError(code: "CAMERA_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    // MARK: - Device Selection

    /// Pilih device kamera:
    /// 1. Jika `cameraId` ada, gunakan device dengan ID tersebut
    /// 2. Jika tidak, fallback ke wide angle camera sesuai posisi
    private func getDevice(cameraId: String?, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let id = cameraId, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - Anti-Macro

    func setAntiMacroEnabled(_ enabled: Bool, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Kamera belum diinisialisasi", details: nil))
            return
        }
        if enabled { setupAntiMacro(device: device) } else { disableAntiMacro(device: device) }
        result(nil)
    }

    /// Mencegah iOS otomatis berpindah ke lensa ultra-wide (macro) pada iPhone 13 Pro ke atas.
    ///
    /// Pada iOS 15+, menggunakan `setPrimaryConstituentDeviceSwitchingBehavior(_:restrictedSwitchingBehaviorConditions:)`.
    /// Pada iOS < 15, hanya menggunakan wide-angle camera secara eksplisit.
    private func setupAntiMacro(device: AVCaptureDevice) {
        if #available(iOS 15.0, *) {
            guard device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported else {
                // Perangkat ini tidak mendukung virtual camera switching — tidak diperlukan
                return
            }
            do {
                try device.lockForConfiguration()
                // .restricted dengan condition kosong = tidak pernah auto-switch
                device.setPrimaryConstituentDeviceSwitchingBehavior(
                    .restricted,
                    restrictedSwitchingBehaviorConditions: []
                )
                device.unlockForConfiguration()
            } catch {
                sendEvent(["event": "error", "message": "Anti-macro setup gagal: \(error.localizedDescription)"])
            }
        }
        // Amati jika ada perubahan lensa
        observeMacroSwitching(device: device)
    }

    private func disableAntiMacro(device: AVCaptureDevice) {
        if #available(iOS 15.0, *) {
            guard device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported else { return }
            do {
                try device.lockForConfiguration()
                device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
                device.unlockForConfiguration()
            } catch {}
        }
        NotificationCenter.default.removeObserver(self, name: AVCaptureDevice.wasDisconnectedNotification, object: device)
    }

    private func observeMacroSwitching(device: AVCaptureDevice) {
        if #available(iOS 15.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onPrimaryConstituentDeviceChanged(_:)),
                name: Notification.Name("AVCaptureDevicePrimaryConstituentDeviceDidChangeNotification"),
                object: device
            )
        }
    }

    @objc private func onPrimaryConstituentDeviceChanged(_ notification: Notification) {
        sendEvent(["event": "macroDetected", "message": "Kamera mencoba berpindah ke lensa ultra-wide/macro — anti-macro aktif"])
    }

    // MARK: - Flash

    func setFlashMode(_ mode: String, result: @escaping FlutterResult) {
        let flashMode: AVCaptureDevice.FlashMode
        switch mode {
        case "on":   flashMode = .on
        case "auto": flashMode = .auto
        default:     flashMode = .off
        }
        currentFlashMode = flashMode
        result(nil)
    }

    // MARK: - Torch

    func setTorchMode(_ enabled: Bool, level: Float, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "TORCH_ERROR", message: "Kamera belum diinisialisasi", details: nil))
            return
        }
        guard device.hasTorch else {
            result(FlutterError(code: "TORCH_ERROR", message: "Perangkat ini tidak memiliki torch", details: nil))
            return
        }
        do {
            try device.lockForConfiguration()
            if enabled {
                let clampedLevel = min(max(level, 0.01), 1.0)
                try device.setTorchModeOn(level: clampedLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "TORCH_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Zoom

    func setZoomLevel(_ zoom: CGFloat, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "ZOOM_ERROR", message: "Kamera belum diinisialisasi", details: nil))
            return
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                                         min(zoom, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "ZOOM_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    func getZoomRange(result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(["min": 1.0, "max": 1.0, "current": 1.0])
            return
        }
        result([
            "min": device.minAvailableVideoZoomFactor,
            "max": device.maxAvailableVideoZoomFactor,
            "current": device.videoZoomFactor,
        ])
    }

    // MARK: - Focus

    func setFocusPoint(x: Double, y: Double, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "FOCUS_ERROR", message: "Kamera belum diinisialisasi", details: nil))
            return
        }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: x, y: y)
                device.focusMode = .autoFocus
            }
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "FOCUS_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Exposure

    func setExposurePoint(x: Double, y: Double, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "EXPOSURE_ERROR", message: "Kamera belum diinisialisasi", details: nil))
            return
        }
        do {
            try device.lockForConfiguration()
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: x, y: y)
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "EXPOSURE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    func setExposureCompensation(_ ev: Float, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "EXPOSURE_ERROR", message: "Kamera belum diinisialisasi", details: nil))
            return
        }
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(
                max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias)),
                completionHandler: nil
            )
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "EXPOSURE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Switch Camera

    /// Toggle depan/belakang
    func switchCamera(result: @escaping FlutterResult) {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        guard let newDevice = getDevice(cameraId: nil, position: newPosition) else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Gagal mengganti kamera", details: nil))
            return
        }
        performSwitch(to: newDevice, newPosition: newPosition, result: result) {
            newPosition == .front ? "front" : "back"
        }
    }

    /// Ganti ke kamera spesifik berdasarkan uniqueId
    func switchToCamera(cameraId: String, result: @escaping FlutterResult) {
        guard let newDevice = AVCaptureDevice(uniqueID: cameraId) else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Kamera dengan ID \(cameraId) tidak ditemukan", details: nil))
            return
        }
        let newPosition = newDevice.position
        performSwitch(to: newDevice, newPosition: newPosition, result: result) {
            newPosition == .front ? "front" : "back"
        }
    }

    private func performSwitch(
        to newDevice: AVCaptureDevice,
        newPosition: AVCaptureDevice.Position,
        result: @escaping FlutterResult,
        resultValue: @escaping () -> String
    ) {
        guard let currentSession = session else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Session tidak tersedia", details: nil))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            currentSession.beginConfiguration()
            for input in currentSession.inputs { currentSession.removeInput(input) }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if currentSession.canAddInput(newInput) {
                    currentSession.addInput(newInput)
                    self?.currentDevice = newDevice
                    self?.currentCameraPosition = newPosition
                }
                currentSession.commitConfiguration()
                DispatchQueue.main.async { result(resultValue()) }
            } catch {
                currentSession.commitConfiguration()
                DispatchQueue.main.async {
                    result(FlutterError(code: "CAMERA_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    // MARK: - Take Picture

    func takePicture(result: @escaping FlutterResult) {
        guard let photoOutput = photoOutput else {
            result(FlutterError(code: "CAPTURE_ERROR", message: "Output foto tidak tersedia", details: nil))
            return
        }
        pendingPhotoResult = result
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(currentFlashMode) {
            settings.flashMode = currentFlashMode
        }
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Video Recording

    func startVideoRecording(result: @escaping FlutterResult) {
        guard let videoOutput = videoOutput, !isRecordingVideo else {
            result(FlutterError(
                code: "RECORD_ERROR",
                message: isRecordingVideo ? "Sudah merekam" : "Output video tidak tersedia",
                details: nil
            ))
            return
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera_video_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: fileURL)
        videoOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecordingVideo = true
        result(nil)
    }

    func stopVideoRecording(result: @escaping FlutterResult) {
        guard let videoOutput = videoOutput, isRecordingVideo else {
            result(FlutterError(code: "RECORD_ERROR", message: "Tidak sedang merekam", details: nil))
            return
        }
        videoOutput.stopRecording()
        isRecordingVideo = false
        result(nil)
    }

    // MARK: - Dispose

    func dispose() {
        NotificationCenter.default.removeObserver(self)
        session?.stopRunning()
        session = nil
        currentDevice = nil
        photoOutput = nil
        videoOutput = nil
        eventSink = nil
        pendingPhotoResult = nil
    }

    // MARK: - Helpers

    func sendEvent(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.eventSink?(data) }
    }

    private func mapResolutionPreset(_ resolution: String) -> AVCaptureSession.Preset {
        switch resolution {
        case "low":       return .low
        case "medium":    return .medium
        case "high":      return .high
        case "veryHigh":  return .hd1920x1080
        case "ultraHigh": return .hd4K3840x2160
        default:          return .high
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let result = pendingPhotoResult else { return }
        pendingPhotoResult = nil

        if let error = error {
            result(FlutterError(code: "CAPTURE_ERROR", message: error.localizedDescription, details: nil))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            result(FlutterError(code: "CAPTURE_ERROR", message: "Gagal mendapatkan data foto", details: nil))
            return
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera_photo_\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: fileURL)
            result(fileURL.path)
        } catch {
            result(FlutterError(code: "CAPTURE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            sendEvent(["event": "error", "message": error.localizedDescription])
        } else {
            sendEvent(["event": "videoRecordingStopped", "path": outputFileURL.path])
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        sendEvent(["event": "videoRecordingStarted"])
    }
}
