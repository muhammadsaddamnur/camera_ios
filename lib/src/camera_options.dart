import 'camera_enums.dart';

/// Opsi inisialisasi kamera
class CameraOptions {
  const CameraOptions({
    this.lensDirection = CameraLensDirection.back,
    this.resolution = ResolutionPreset.high,
    this.enableAntiMacro = false,
    this.enableAudio = true,
    this.autoFlash = false,
  });

  /// Arah lensa (depan/belakang)
  final CameraLensDirection lensDirection;

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
      'lensDirection': lensDirection.name,
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
