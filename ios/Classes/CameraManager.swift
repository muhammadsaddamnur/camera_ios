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

    // MARK: - Initialize

    func initialize(
        cameraPosition: String,
        resolution: String,
        enableAntiMacro: Bool,
        result: @escaping FlutterResult
    ) {
        let position: AVCaptureDevice.Position = cameraPosition == "front" ? .front : .back
        let preset = mapResolutionPreset(resolution)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupSession(
                position: position,
                preset: preset,
                enableAntiMacro: enableAntiMacro,
                result: result
            )
        }
    }

    private func setupSession(
        position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset,
        enableAntiMacro: Bool,
        result: @escaping FlutterResult
    ) {
        let newSession = AVCaptureSession()
        newSession.beginConfiguration()
        newSession.sessionPreset = preset

        guard let device = getCameraDevice(position: position) else {
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
            // Input
            let input = try AVCaptureDeviceInput(device: device)
            if newSession.canAddInput(input) {
                newSession.addInput(input)
            } else {
                throw NSError(
                    domain: "CameraError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Tidak dapat menambahkan input kamera"]
                )
            }

            // Photo output
            let photoOut = AVCapturePhotoOutput()
            if newSession.canAddOutput(photoOut) {
                newSession.addOutput(photoOut)
            }

            // Video output
            let videoOut = AVCaptureMovieFileOutput()
            if newSession.canAddOutput(videoOut) {
                newSession.addOutput(videoOut)
            }

            newSession.commitConfiguration()

            // Simpan referensi
            session = newSession
            currentDevice = device
            photoOutput = photoOut
            videoOutput = videoOut
            currentCameraPosition = position

            // Preview layer dibuat oleh CameraLayerView (layerClass override),
            // CameraManager hanya menyimpan session.

            // Jalankan session
            newSession.startRunning()

            // Setup anti-macro jika diminta
            if enableAntiMacro {
                setupAntiMacro(device: device)
            }

            DispatchQueue.main.async { [weak self] in
                result(nil)
                self?.sendEvent(["event": "cameraInitialized"])
            }

        } catch {
            newSession.commitConfiguration()
            DispatchQueue.main.async {
                result(FlutterError(
                    code: "CAMERA_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    // MARK: - Device Selection

    /// Selalu gunakan built-in wide angle camera agar tidak auto-switch ke macro/ultra-wide
    private func getCameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Prioritas: Wide angle (aman dari macro switching)
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - Anti-Macro

    func setAntiMacroEnabled(_ enabled: Bool, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Kamera belum diinisialisasi", details: nil))
            return
        }
        if enabled {
            setupAntiMacro(device: device)
        } else {
            disableAntiMacro(device: device)
        }
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
        NotificationCenter.default.removeObserver(
            self,
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: device
        )
    }

    private func observeMacroSwitching(device: AVCaptureDevice) {
        // Amati konstituen device berubah (iOS 15+ virtual multi-camera switching)
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
        sendEvent([
            "event": "macroDetected",
            "message": "Kamera mencoba berpindah ke lensa ultra-wide/macro — anti-macro aktif"
        ])
    }

    // MARK: - Flash

    func setFlashMode(_ mode: String, result: @escaping FlutterResult) {
        let flashMode: AVCaptureDevice.FlashMode
        switch mode {
        case "on": flashMode = .on
        case "auto": flashMode = .auto
        default: flashMode = .off
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
                // setTorchModeOn(level:) tidak menerima 0.0, clamp ke minimum 0.01
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
            let clamped = max(device.minAvailableVideoZoomFactor,
                              min(zoom, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = clamped
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
            let point = CGPoint(x: x, y: y)
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
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
            let point = CGPoint(x: x, y: y)
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
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
            let clamped = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "EXPOSURE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Switch Camera

    func switchCamera(result: @escaping FlutterResult) {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        guard let newDevice = getCameraDevice(position: newPosition),
              let currentSession = session else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Gagal mengganti kamera", details: nil))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            currentSession.beginConfiguration()

            // Hapus semua input
            for input in currentSession.inputs {
                currentSession.removeInput(input)
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if currentSession.canAddInput(newInput) {
                    currentSession.addInput(newInput)
                    self?.currentDevice = newDevice
                    self?.currentCameraPosition = newPosition
                }
                currentSession.commitConfiguration()

                DispatchQueue.main.async {
                    result(newPosition == .front ? "front" : "back")
                }
            } catch {
                currentSession.commitConfiguration()
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "CAMERA_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
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

        // Set flash mode
        if photoOutput.supportedFlashModes.contains(currentFlashMode) {
            settings.flashMode = currentFlashMode
        }

        // High quality jika tersedia
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

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "camera_video_\(Int(Date().timeIntervalSince1970)).mp4"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // Hapus file lama jika ada
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
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }

    private func mapResolutionPreset(_ resolution: String) -> AVCaptureSession.Preset {
        switch resolution {
        case "low": return .low
        case "medium": return .medium
        case "high": return .high
        case "veryHigh": return .hd1920x1080
        case "ultraHigh": return .hd4K3840x2160
        default: return .high
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
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

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "camera_photo_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = tempDir.appendingPathComponent(fileName)

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

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error = error {
            sendEvent(["event": "error", "message": error.localizedDescription])
        } else {
            sendEvent(["event": "videoRecordingStopped", "path": outputFileURL.path])
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        sendEvent(["event": "videoRecordingStarted"])
    }
}
