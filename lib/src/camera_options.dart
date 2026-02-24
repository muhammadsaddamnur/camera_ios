import 'camera_description.dart';
import 'camera_enums.dart';

/// Opsi inisialisasi kamera.
///
/// Jika [camera] disediakan, field ini mengambil prioritas atas [lensDirection]
/// dan kamera persis tersebut yang akan dipakai (berdasarkan [CameraDescription.uniqueId]).
class CameraOptions {
  const CameraOptions({
    this.lensDirection = CameraLensDirection.back,
    this.camera,
    this.resolution = ResolutionPreset.high,
    this.enableAntiMacro = false,
    this.enableAudio = true,
    this.autoFlash = false,
  });

  /// Arah lensa (depan/belakang) — diabaikan jika [camera] disediakan
  final CameraLensDirection lensDirection;

  /// Kamera spesifik dari [CameraController.availableCameras()].
  /// Jika null, [lensDirection] digunakan sebagai fallback.
  final CameraDescription? camera;

  /// Preset resolusi
  final ResolutionPreset resolution;

  /// Aktifkan anti-macro otomatis sejak awal
  final bool enableAntiMacro;

  /// Rekam audio saat video recording
  final bool enableAudio;

  /// Flash otomatis saat kondisi gelap
  final bool autoFlash;

  Map<String, dynamic> toMap() {
    return {
      'lensDirection': camera?.lensDirection.name ?? lensDirection.name,
      'cameraId': camera?.uniqueId,
      'resolution': resolution.name,
      'enableAntiMacro': enableAntiMacro,
      'enableAudio': enableAudio,
      'autoFlash': autoFlash,
    };
  }
}

/// Event dari kamera native
class CameraEvent {
  const CameraEvent({
    required this.type,
    this.data,
  });

  final CameraEventType type;
  final Map<String, dynamic>? data;

  static CameraEvent fromMap(Map<dynamic, dynamic> map) {
    final eventStr = map['event'] as String? ?? '';
    final type = switch (eventStr) {
      'cameraInitialized' => CameraEventType.initialized,
      'pictureTaken' => CameraEventType.pictureTaken,
      'videoRecordingStarted' => CameraEventType.videoRecordingStarted,
      'videoRecordingStopped' => CameraEventType.videoRecordingStopped,
      'macroDetected' => CameraEventType.macroDetected,
      _ => CameraEventType.error,
    };

    final data = Map<String, dynamic>.from(
      map.map((k, v) => MapEntry(k.toString(), v)),
    );

    return CameraEvent(type: type, data: data);
  }
}
