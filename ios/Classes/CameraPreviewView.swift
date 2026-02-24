import Flutter
import UIKit
import AVFoundation

// MARK: - Factory

class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {

    private let cameraManager: CameraManager

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return CameraPreviewView(frame: frame, cameraManager: cameraManager)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Platform View

class CameraPreviewView: NSObject, FlutterPlatformView {

    private let previewView: CameraLayerView
    private let cameraManager: CameraManager

    init(frame: CGRect, cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        self.previewView = CameraLayerView(frame: frame)
        super.init()

        // Sambungkan session ke preview layer.
        // UiKitView hanya ditampilkan setelah isInitialized=true,
        // jadi session sudah pasti ada di sini.
        if let session = cameraManager.session {
            previewView.connectSession(session)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    func view() -> UIView {
        return previewView
    }

    @objc private func orientationChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.previewView.updateOrientation()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - CameraLayerView

/// UIView yang menggunakan AVCaptureVideoPreviewLayer sebagai backing layer (via layerClass).
///
/// Pendekatan ini paling andal karena:
/// - Layer selalu seukuran view (auto-resize otomatis oleh UIKit)
/// - Tidak perlu manually update frame
/// - Tidak ada masalah urutan insert sublayer
class CameraLayerView: UIView {

    /// Override layerClass agar UIView.layer == AVCaptureVideoPreviewLayer
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        return layer as! AVCaptureVideoPreviewLayer
    }

    /// Sambungkan AVCaptureSession ke preview layer.
    func connectSession(_ session: AVCaptureSession) {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        updateOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Frame diurus otomatis oleh UIKit karena layerClass override.
        // Kita hanya perlu update orientasi saat layout berubah.
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else { return }

        let interfaceOrientation: UIInterfaceOrientation

        if #available(iOS 16.0, *) {
            // iOS 16+: gunakan keyWindow.windowScene
            interfaceOrientation = UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .interfaceOrientation ?? .portrait
        } else {
            interfaceOrientation = UIApplication.shared.windows
                .first(where: { $0.isKeyWindow })?
                .windowScene?
                .interfaceOrientation ?? .portrait
        }

        connection.videoOrientation = mapToVideoOrientation(interfaceOrientation)
    }

    private func mapToVideoOrientation(_ orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft:      return .landscapeLeft
        case .landscapeRight:     return .landscapeRight
        default:                  return .portrait
        }
    }
}
