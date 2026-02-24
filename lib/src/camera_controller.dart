import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'camera_description.dart';
import 'camera_enums.dart';
import 'camera_exception.dart';
import 'camera_options.dart';
import 'camera_value.dart';

/// Controller utama untuk mengontrol kamera iOS.
///
/// Contoh penggunaan:
/// ```dart
/// // 1. Dapatkan daftar kamera
/// final cameras = await CameraController.availableCameras();
///
/// // 2. Pilih kamera yang diinginkan
/// final backWide = cameras.firstWhere(
///   (c) => c.lensDirection == CameraLensDirection.back
///         && c.deviceType == CameraDeviceType.wideAngle,
/// );
///
/// // 3. Inisialisasi controller
/// final controller = CameraController();
/// await controller.initialize(
///   options: CameraOptions(camera: backWide, enableAntiMacro: true),
/// );
/// ```
class CameraController extends ValueNotifier<CameraValue> {
  CameraController() : super(const CameraValue.uninitialized());

  static const MethodChannel _channel = MethodChannel('ios_camera_pro');
  static const EventChannel _eventChannel = EventChannel('ios_camera_pro/events');

  StreamSubscription<dynamic>? _eventSubscription;
  final StreamController<CameraEvent> _cameraEventController =
      StreamController<CameraEvent>.broadcast();

  /// Stream semua event dari kamera (macro detected, error, dsb)
  Stream<CameraEvent> get cameraEvents => _cameraEventController.stream;

  /// Stream khusus event macro terdeteksi
  Stream<CameraEvent> get onMacroDetected =>
      cameraEvents.where((e) => e.type == CameraEventType.macroDetected);

  bool _isDisposed = false;

  // ─────────────────────────────────────────
  // AVAILABLE CAMERAS (static)
  // ─────────────────────────────────────────

  /// Dapatkan daftar semua kamera yang tersedia di perangkat.
  ///
  /// Mirip dengan `availableCameras()` dari package `camera`.
  ///
  /// ```dart
  /// final cameras = await CameraController.availableCameras();
  /// // cameras berisi wide angle, ultrawide, telephoto, front, dll
  /// ```
  static Future<List<CameraDescription>> availableCameras() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('getAvailableCameras') ?? [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(CameraDescription.fromMap)
          .toList();
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // INIT & DISPOSE
  // ─────────────────────────────────────────

  /// Inisialisasi kamera dengan opsi yang ditentukan.
  ///
  /// Jika [options.camera] disediakan, kamera spesifik tersebut yang digunakan.
  /// Jika tidak, [options.lensDirection] digunakan sebagai fallback.
  Future<void> initialize({
    CameraOptions options = const CameraOptions(),
  }) async {
    _checkNotDisposed();
    _startListeningEvents();

    try {
      await _channel.invokeMethod<void>('initialize', options.toMap());
      if (_isDisposed) return;
      final zoomRange =
          await _channel.invokeMapMethod<String, dynamic>('getZoomRange') ?? {};
      if (_isDisposed) return;

      value = value.copyWith(
        isInitialized: true,
        lensDirection: options.camera?.lensDirection ?? options.lensDirection,
        activeCamera: options.camera,
        antiMacroEnabled: options.enableAntiMacro,
        flashMode: options.autoFlash ? FlashMode.auto : FlashMode.off,
        minZoomLevel: (zoomRange['min'] as num?)?.toDouble() ?? 1.0,
        maxZoomLevel: (zoomRange['max'] as num?)?.toDouble() ?? 10.0,
        zoomLevel: (zoomRange['current'] as num?)?.toDouble() ?? 1.0,
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Lepaskan semua resource kamera.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _cameraEventController.close();

    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException catch (_) {}

    super.dispose();
  }

  // ─────────────────────────────────────────
  // ANTI-MACRO
  // ─────────────────────────────────────────

  /// Aktifkan/nonaktifkan fitur anti-macro.
  Future<void> setAntiMacroEnabled(bool enabled) async {
    _checkInitialized();
    try {
      await _channel.invokeMethod<void>('setAntiMacroEnabled', {'enabled': enabled});
      value = value.copyWith(antiMacroEnabled: enabled);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // FLASH & TORCH
  // ─────────────────────────────────────────

  /// Set mode flash.
  Future<void> setFlashMode(FlashMode mode) async {
    _checkInitialized();
    try {
      if (mode == FlashMode.torch) {
        await _channel.invokeMethod<void>('setTorchMode', {
          'enabled': true,
          'level': value.torchLevel,
        });
        value = value.copyWith(flashMode: FlashMode.torch, isTorchOn: true);
      } else {
        if (value.isTorchOn) {
          await _channel.invokeMethod<void>('setTorchMode', {'enabled': false, 'level': 1.0});
        }
        await _channel.invokeMethod<void>('setFlashMode', {'mode': mode.name});
        value = value.copyWith(flashMode: mode, isTorchOn: false);
      }
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Nyalakan/matikan torch. [level] antara 0.0–1.0.
  Future<void> setTorchMode({bool enabled = true, double level = 1.0}) async {
    _checkInitialized();
    assert(level >= 0.0 && level <= 1.0);
    try {
      await _channel.invokeMethod<void>('setTorchMode', {
        'enabled': enabled,
        'level': level.clamp(0.0, 1.0),
      });
      value = value.copyWith(
        isTorchOn: enabled,
        torchLevel: level,
        flashMode: enabled ? FlashMode.torch : value.flashMode,
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // ZOOM
  // ─────────────────────────────────────────

  /// Set level zoom. Akan di-clamp ke [minZoomLevel]..[maxZoomLevel].
  Future<void> setZoomLevel(double zoom) async {
    _checkInitialized();
    final clamped = zoom.clamp(value.minZoomLevel, value.maxZoomLevel);
    try {
      await _channel.invokeMethod<void>('setZoomLevel', {'zoom': clamped});
      value = value.copyWith(zoomLevel: clamped);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // FOKUS & EXPOSURE
  // ─────────────────────────────────────────

  /// Set titik fokus (normalized 0.0–1.0).
  Future<void> setFocusPoint(double x, double y) async {
    _checkInitialized();
    try {
      await _channel.invokeMethod<void>('setFocusPoint', {'x': x, 'y': y});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set titik exposure (normalized 0.0–1.0).
  Future<void> setExposurePoint(double x, double y) async {
    _checkInitialized();
    try {
      await _channel.invokeMethod<void>('setExposurePoint', {'x': x, 'y': y});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set exposure compensation dalam EV (biasanya -2.0 hingga +2.0).
  Future<void> setExposureCompensation(double ev) async {
    _checkInitialized();
    try {
      await _channel.invokeMethod<void>('setExposureCompensation', {'ev': ev});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // GANTI KAMERA
  // ─────────────────────────────────────────

  /// Toggle antara kamera depan dan belakang.
  Future<void> switchCamera() async {
    _checkInitialized();
    try {
      final result = await _channel.invokeMethod<String>('switchCamera');
      final newDirection =
          result == 'front' ? CameraLensDirection.front : CameraLensDirection.back;
      value = value.copyWith(lensDirection: newDirection, activeCamera: null);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Ganti ke kamera spesifik dari [availableCameras].
  ///
  /// ```dart
  /// final cameras = await CameraController.availableCameras();
  /// final telephoto = cameras.firstWhere(
  ///   (c) => c.deviceType == CameraDeviceType.telephoto,
  /// );
  /// await controller.switchToCamera(telephoto);
  /// ```
  Future<void> switchToCamera(CameraDescription camera) async {
    _checkInitialized();
    try {
      await _channel.invokeMethod<void>('switchToCamera', {'cameraId': camera.uniqueId});

      final zoomRange =
          await _channel.invokeMapMethod<String, dynamic>('getZoomRange') ?? {};
      value = value.copyWith(
        lensDirection: camera.lensDirection,
        activeCamera: camera,
        minZoomLevel: (zoomRange['min'] as num?)?.toDouble() ?? 1.0,
        maxZoomLevel: (zoomRange['max'] as num?)?.toDouble() ?? 10.0,
        zoomLevel: (zoomRange['current'] as num?)?.toDouble() ?? 1.0,
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // ASPECT RATIO
  // ─────────────────────────────────────────

  /// Set aspect ratio preview (width / height).
  ///
  /// Gunakan konstanta dari [CameraAspectRatio]:
  /// ```dart
  /// controller.setAspectRatio(CameraAspectRatio.ratio16x9.ratio); // 16/9
  /// controller.setAspectRatio(CameraAspectRatio.ratio4x3.ratio);  // 4/3
  /// controller.setAspectRatio(null); // full screen
  /// ```
  void setAspectRatio(double? ratio) {
    _checkInitialized();
    if (ratio == null) {
      value = value.clearAspectRatio();
    } else {
      value = value.copyWith(aspectRatio: ratio);
    }
  }

  // ─────────────────────────────────────────
  // FOTO
  // ─────────────────────────────────────────

  /// Ambil foto dan kembalikan path file-nya.
  Future<String> takePicture() async {
    _checkInitialized();
    if (value.isTakingPicture) {
      throw const CameraException('CAPTURE_ERROR', 'Sedang mengambil foto');
    }
    value = value.copyWith(isTakingPicture: true);
    try {
      final path = await _channel.invokeMethod<String>('takePicture');
      if (path == null) throw const CameraException('CAPTURE_ERROR', 'Path foto kosong');
      return path;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    } finally {
      value = value.copyWith(isTakingPicture: false);
    }
  }

  // ─────────────────────────────────────────
  // VIDEO
  // ─────────────────────────────────────────

  /// Mulai rekam video.
  Future<void> startVideoRecording() async {
    _checkInitialized();
    if (value.isRecordingVideo) {
      throw const CameraException('RECORD_ERROR', 'Sudah dalam kondisi merekam');
    }
    try {
      await _channel.invokeMethod<void>('startVideoRecording');
      value = value.copyWith(isRecordingVideo: true);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Stop rekam video.
  Future<void> stopVideoRecording() async {
    _checkInitialized();
    if (!value.isRecordingVideo) {
      throw const CameraException('RECORD_ERROR', 'Tidak sedang merekam');
    }
    try {
      await _channel.invokeMethod<void>('stopVideoRecording');
      value = value.copyWith(isRecordingVideo: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // PRIVATE HELPERS
  // ─────────────────────────────────────────

  void _startListeningEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is Map) {
          final event = CameraEvent.fromMap(data);
          _cameraEventController.add(event);
          switch (event.type) {
            case CameraEventType.macroDetected:
              value = value.copyWith(isMacroDetected: true);
            case CameraEventType.error:
              value = value.copyWith(
                  errorDescription: event.data?['message']?.toString());
            default:
              break;
          }
        }
      },
      onError: (dynamic error) {
        if (error is PlatformException) {
          _cameraEventController
              .addError(CameraException(error.code, error.message));
        }
      },
    );
  }

  void _checkInitialized() {
    _checkNotDisposed();
    if (!value.isInitialized) {
      throw const CameraException(
          'NOT_INITIALIZED', 'Panggil initialize() terlebih dahulu');
    }
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw const CameraException('DISPOSED', 'Controller sudah di-dispose');
    }
  }
}
