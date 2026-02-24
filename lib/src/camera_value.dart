import 'camera_enums.dart';

/// Menyimpan state kamera saat ini
class CameraValue {
  const CameraValue({
    required this.isInitialized,
    this.isRecordingVideo = false,
    this.isTakingPicture = false,
    this.isStreamingImages = false,
    this.flashMode = FlashMode.off,
    this.focusMode = FocusMode.auto,
    this.exposureMode = ExposureMode.auto,
    this.zoomLevel = 1.0,
    this.minZoomLevel = 1.0,
    this.maxZoomLevel = 1.0,
    this.isTorchOn = false,
    this.torchLevel = 1.0,
    this.antiMacroEnabled = false,
    this.isMacroDetected = false,
    this.lensDirection = CameraLensDirection.back,
    this.errorDescription,
    this.previewSize,
  });

  const CameraValue.uninitialized()
      : this(isInitialized: false);

  final bool isInitialized;
  final bool isRecordingVideo;
  final bool isTakingPicture;
  final bool isStreamingImages;
  final FlashMode flashMode;
  final FocusMode focusMode;
  final ExposureMode exposureMode;
  final double zoomLevel;
  final double minZoomLevel;
  final double maxZoomLevel;
  final bool isTorchOn;
  final double torchLevel;
  final bool antiMacroEnabled;
  final bool isMacroDetected;
  final CameraLensDirection lensDirection;
  final String? errorDescription;
  final CameraSize? previewSize;

  CameraValue copyWith({
    bool? isInitialized,
    bool? isRecordingVideo,
    bool? isTakingPicture,
    bool? isStreamingImages,
    FlashMode? flashMode,
    FocusMode? focusMode,
    ExposureMode? exposureMode,
    double? zoomLevel,
    double? minZoomLevel,
    double? maxZoomLevel,
    bool? isTorchOn,
    double? torchLevel,
    bool? antiMacroEnabled,
    bool? isMacroDetected,
    CameraLensDirection? lensDirection,
    String? errorDescription,
    CameraSize? previewSize,
  }) {
    return CameraValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isRecordingVideo: isRecordingVideo ?? this.isRecordingVideo,
      isTakingPicture: isTakingPicture ?? this.isTakingPicture,
      isStreamingImages: isStreamingImages ?? this.isStreamingImages,
      flashMode: flashMode ?? this.flashMode,
      focusMode: focusMode ?? this.focusMode,
      exposureMode: exposureMode ?? this.exposureMode,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      minZoomLevel: minZoomLevel ?? this.minZoomLevel,
      maxZoomLevel: maxZoomLevel ?? this.maxZoomLevel,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      torchLevel: torchLevel ?? this.torchLevel,
      antiMacroEnabled: antiMacroEnabled ?? this.antiMacroEnabled,
      isMacroDetected: isMacroDetected ?? this.isMacroDetected,
      lensDirection: lensDirection ?? this.lensDirection,
      errorDescription: errorDescription,
        previewSize: previewSize ?? this.previewSize,
    );
  }

  @override
  String toString() {
    return 'CameraValue('
        'isInitialized: $isInitialized, '
        'isRecordingVideo: $isRecordingVideo, '
        'flashMode: $flashMode, '
        'zoomLevel: $zoomLevel, '
        'antiMacroEnabled: $antiMacroEnabled'
        ')';
  }
}

/// Ukuran preview kamera (agar tidak konflik dengan Flutter's Size)
class CameraSize {
  const CameraSize(this.width, this.height);

  final double width;
  final double height;

  @override
  String toString() => 'CameraSize($width, $height)';
}
