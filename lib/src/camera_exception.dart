/// Exception yang dilempar ketika terjadi error pada kamera
class CameraException implements Exception {
  const CameraException(this.code, this.description);

  /// Kode error
  final String code;

  /// Deskripsi error yang dapat dibaca manusia
  final String? description;

  @override
  String toString() => 'CameraException($code, $description)';
}
