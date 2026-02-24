/// Flutter plugin untuk kamera iOS dengan fitur lengkap:
/// - [CameraController.availableCameras] — daftar semua kamera fisik di perangkat
/// - [CameraDescription] — info kamera (nama, jenis lensa, sensor orientation, aspect ratio)
/// - Anti-macro (mencegah kamera auto-switch ke lensa ultra-wide/macro)
/// - Flash control (off/auto/on/torch)
/// - Torch dengan level brightness yang dapat diatur
/// - Zoom control
/// - Focus & Exposure control
/// - Photo capture & Video recording
/// - Ganti kamera (depan/belakang, atau spesifik via [CameraController.switchToCamera])
/// - Aspect ratio preview
library ios_camera_pro;

export 'src/camera_controller.dart';
export 'src/camera_description.dart';
export 'src/camera_enums.dart';
export 'src/camera_exception.dart';
export 'src/camera_options.dart';
export 'src/camera_preview_widget.dart';
export 'src/camera_value.dart';
