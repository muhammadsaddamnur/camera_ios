import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'camera_enums.dart';
import 'camera_exception.dart';
import 'camera_options.dart';
import 'camera_value.dart';

/// Controller utama untuk mengontrol kamera iOS.
///
/// Contoh penggunaan:
/// ```dart
/// final controller = CameraController();
/// await controller.initialize(
///   options: CameraOptions(
///     lensDirection: CameraLensDirection.back,
///     resolution: ResolutionPreset.high,
///     enableAntiMacro: true,
///   ),
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
  Stream<CameraEvent> get onMacroDetected => cameraEvents.where(
        (e) => e.type == CameraEventType.macroDetected,
      );

  bool _isDisposed = false;

  // ─────────────────────────────────────────
  // INIT & DISPOSE
  // ─────────────────────────────────────────

  /// Inisialisasi kamera dengan opsi yang ditentukan.
  Future<void> initialize({
    CameraOptions options = const CameraOptions(),
  }) async {
    _checkNotDisposed();

    _startListeningEvents();

    try {
      await _channel.invokeMethod<void>('initialize', options.toMap());
      final zoomRange = await _channel.invokeMapMethod<String, dynamic>('getZoomRange') ?? {};

      value = value.copyWith(
        isInitialized: true,
        lensDirection: options.lensDirection,
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
  ///
  /// Ketika aktif, kamera tidak akan otomatis berpindah ke lensa ultra-wide
  /// (macro) pada iPhone 13 Pro ke atas.
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
  ///
  /// [FlashMode.torch] menyalakan flash sebagai senter terus-menerus.
  /// Untuk mode torch gunakan [setTorchMode] agar bisa atur brightness.
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
        // Matikan torch dulu jika sedang menyala
        if (value.isTorchOn) {
          await _channel.invokeMethod<void>('setTorchMode', {
            'enabled': false,
            'level': 1.0,
          });
        }
        await _channel.invokeMethod<void>('setFlashMode', {'mode': mode.name});
        value = value.copyWith(flashMode: mode, isTorchOn: false);
      }
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Nyalakan/matikan torch (flash terus-menerus / senter).
  ///
  /// [level] antara 0.0 - 1.0, default 1.0 (max brightness).
  Future<void> setTorchMode({bool enabled = true, double level = 1.0}) async {
    _checkInitialized();
    assert(level >= 0.0 && level <= 1.0, 'Torch level harus antara 0.0 dan 1.0');

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

  /// Set level zoom kamera.
  ///
  /// [zoom] akan di-clamp ke range [minZoomLevel]..[maxZoomLevel].
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

  /// Set titik fokus kamera.
  ///
  /// [x] dan [y] adalah koordinat normalized (0.0 - 1.0).
  Future<void> setFocusPoint(double x, double y) async {
    _checkInitialized();
    assert(x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0,
        'Koordinat fokus harus antara 0.0 dan 1.0');
    try {
      await _channel.invokeMethod<void>('setFocusPoint', {'x': x, 'y': y});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set exposure compensation (EV).
  ///
  /// Range EV tergantung perangkat, biasanya -2.0 hingga +2.0.
  Future<void> setExposureCompensation(double ev) async {
    _checkInitialized();
    try {
      await _channel.invokeMethod<void>('setExposureCompensation', {'ev': ev});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set titik exposure kamera (normalized 0.0 - 1.0).
  Future<void> setExposurePoint(double x, double y) async {
    _checkInitialized();
    try {
      await _channel.invokeMethod<void>('setExposurePoint', {'x': x, 'y': y});
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // GANTI KAMERA
  // ─────────────────────────────────────────

  /// Ganti antara kamera depan dan belakang.
  Future<void> switchCamera() async {
    _checkInitialized();
    try {
      final result = await _channel.invokeMethod<String>('switchCamera');
      final newDirection = result == 'front'
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      value = value.copyWith(lensDirection: newDirection);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  // ─────────────────────────────────────────
  // FOTO
  // ─────────────────────────────────────────

  /// Ambil foto dan kembalikan path file-nya.
  ///
  /// File disimpan di direktori temporary sistem.
  Future<String> takePicture() async {
    _checkInitialized();
    if (value.isTakingPicture) {
      throw const CameraException('CAPTURE_ERROR', 'Sedang mengambil foto');
    }

    value = value.copyWith(isTakingPicture: true);
    try {
      final path = await _channel.invokeMethod<String>('takePicture');
      if (path == null) {
        throw const CameraException('CAPTURE_ERROR', 'Path foto kosong');
      }
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

  /// Stop rekam video. Event [CameraEventType.videoRecordingStopped]
  /// akan mengandung path file video.
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
                errorDescription: event.data?['message']?.toString(),
              );
            default:
              break;
          }
        }
      },
      onError: (dynamic error) {
        if (error is PlatformException) {
          _cameraEventController.addError(
            CameraException(error.code, error.message),
          );
        }
      },
    );
  }

  void _checkInitialized() {
    _checkNotDisposed();
    if (!value.isInitialized) {
      throw const CameraException(
        'NOT_INITIALIZED',
        'Panggil initialize() terlebih dahulu',
      );
    }
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw const CameraException(
        'DISPOSED',
        'Controller sudah di-dispose',
      );
    }
  }
}
