import 'camera_enums.dart';

/// Informasi tentang kamera fisik yang tersedia di perangkat.
///
/// Mirip dengan [CameraDescription] di package `camera` dari Flutter.
///
/// Contoh penggunaan:
/// ```dart
/// final cameras = await CameraController.availableCameras();
/// final back = cameras.firstWhere(
///   (c) => c.lensDirection == CameraLensDirection.back
///         && c.deviceType == CameraDeviceType.wideAngle,
/// );
/// await controller.initialize(camera: back);
/// ```
class CameraDescription {
  const CameraDescription({
    required this.name,
    required this.uniqueId,
    required this.lensDirection,
    required this.sensorOrientation,
    this.hasFlash = false,
    this.hasTorch = false,
    this.deviceType = CameraDeviceType.wideAngle,
    this.availableAspectRatios = const [],
  });

  /// Nama kamera yang dapat dibaca manusia, misal "Back Camera"
  final String name;

  /// ID unik perangkat (AVCaptureDevice.uniqueID dari iOS)
  final String uniqueId;

  /// Arah lensa: depan atau belakang
  final CameraLensDirection lensDirection;

  /// Orientasi sensor dalam derajat.
  /// Biasanya 90 untuk kamera belakang, 270 untuk kamera depan.
  final int sensorOrientation;

  /// Kamera ini memiliki flash
  final bool hasFlash;

  /// Kamera ini memiliki torch (senter)
  final bool hasTorch;

  /// Jenis lensa kamera
  final CameraDeviceType deviceType;

  /// Daftar aspect ratio yang didukung kamera ini
  final List<CameraAspectRatio> availableAspectRatios;

  /// Parse dari Map yang dikirim native iOS
  static CameraDescription fromMap(Map<dynamic, dynamic> map) {
    final ratios = (map['aspectRatios'] as List? ?? [])
        .cast<Map<dynamic, dynamic>>()
        .map(
          (r) => CameraAspectRatio(
            width: (r['width'] as num).toInt(),
            height: (r['height'] as num).toInt(),
          ),
        )
        .toList();

    final lensStr = map['lensDirection'] as String? ?? 'back';
    final lensDirection =
        lensStr == 'front' ? CameraLensDirection.front : CameraLensDirection.back;

    final typeStr = map['deviceType'] as String? ?? 'wideAngle';
    final deviceType = CameraDeviceType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => CameraDeviceType.unknown,
    );

    return CameraDescription(
      name: map['name'] as String? ?? '',
      uniqueId: map['uniqueId'] as String? ?? '',
      lensDirection: lensDirection,
      sensorOrientation: (map['sensorOrientation'] as num?)?.toInt() ?? 90,
      hasFlash: map['hasFlash'] as bool? ?? false,
      hasTorch: map['hasTorch'] as bool? ?? false,
      deviceType: deviceType,
      availableAspectRatios: ratios,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDescription &&
          runtimeType == other.runtimeType &&
          uniqueId == other.uniqueId;

  @override
  int get hashCode => uniqueId.hashCode;

  @override
  String toString() =>
      'CameraDescription(name: $name, direction: $lensDirection, type: $deviceType)';
}

// ─────────────────────────────────────────────────────────────────────────────
// CameraDeviceType
// ─────────────────────────────────────────────────────────────────────────────

/// Jenis lensa kamera fisik
enum CameraDeviceType {
  /// Lensa wide angle — kamera standar (semua iPhone)
  wideAngle,

  /// Lensa ultra-wide — juga berfungsi sebagai macro pada iPhone 13 Pro ke atas
  ultraWide,

  /// Lensa telephoto — zoom optik (Pro models)
  telephoto,

  /// Kamera depan TrueDepth (Face ID camera)
  trueDepth,

  /// Virtual dual camera: wide + telephoto
  dual,

  /// Virtual dual-wide camera: wide + ultraWide
  dualWide,

  /// Virtual triple camera: wide + ultraWide + telephoto (iPhone 13 Pro ke atas)
  triple,

  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
// CameraAspectRatio
// ─────────────────────────────────────────────────────────────────────────────

/// Aspect ratio kamera, direpresentasikan sebagai perbandingan integer width:height.
class CameraAspectRatio {
  const CameraAspectRatio({required this.width, required this.height});

  final int width;
  final int height;

  /// Nilai ratio sebagai double (misal 1.3333 untuk 4:3)
  double get ratio => width / height;

  // ── Preset umum ──────────────────────────────────
  static const ratio1x1 = CameraAspectRatio(width: 1, height: 1);
  static const ratio4x3 = CameraAspectRatio(width: 4, height: 3);
  static const ratio3x2 = CameraAspectRatio(width: 3, height: 2);
  static const ratio16x9 = CameraAspectRatio(width: 16, height: 9);

  @override
  bool operator ==(Object other) =>
      other is CameraAspectRatio && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '$width:$height';
}
