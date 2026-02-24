/// Arah lensa kamera
enum CameraLensDirection { front, back }

/// Mode flash kamera
enum FlashMode {
  /// Flash mati
  off,

  /// Flash otomatis (menyala saat kondisi gelap)
  auto,

  /// Flash selalu menyala saat capture
  on,

  /// Torch (flash terus menyala sebagai senter)
  torch,
}

/// Preset resolusi kamera
enum ResolutionPreset {
  /// 352x288
  low,

  /// 480p
  medium,

  /// 720p
  high,

  /// 1080p
  veryHigh,

  /// 4K (jika tersedia)
  ultraHigh,
}

/// Mode fokus kamera
enum FocusMode {
  /// Fokus otomatis (auto focus sekali)
  auto,

  /// Fokus terkunci pada posisi saat ini
  locked,

  /// Fokus terus-menerus (continuous auto focus)
  continuous,
}

/// Mode exposure kamera
enum ExposureMode {
  /// Exposure otomatis
  auto,

  /// Exposure terkunci
  locked,

  /// Exposure terus-menerus
  continuous,
}

/// Event dari kamera
enum CameraEventType {
  initialized,
  pictureTaken,
  videoRecordingStarted,
  videoRecordingStopped,
  macroDetected,
  error,
}
