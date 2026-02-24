import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ios_camera_pro/ios_camera_pro.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iOS Camera Pro Demo',
      theme: ThemeData.dark(),
      home: const CameraScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera Screen
// ─────────────────────────────────────────────────────────────────────────────

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final CameraController _controller = CameraController();

  List<CameraDescription> _availableCameras = [];
  StreamSubscription<CameraEvent>? _macroSub;

  bool _isInitializing = true;
  String? _errorMessage;
  String? _lastPhotoPath;
  double? _lastZoom;
  Offset? _focusTapPosition;

  // Aspect ratio yang dipilih (null = full screen)
  double? _selectedAspectRatio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameras();
  }

  /// Langkah 1: load daftar kamera dulu, lalu init dengan kamera belakang standar
  Future<void> _loadCameras() async {
    try {
      final cameras = await CameraController.availableCameras();
      if (mounted) setState(() => _availableCameras = cameras);

      // Pilih wide angle belakang sebagai default
      final defaultCamera = _findCamera(
        cameras,
        direction: CameraLensDirection.back,
        type: CameraDeviceType.wideAngle,
      );

      await _initWithCamera(defaultCamera);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '${e.code}: ${e.description}';
        });
      }
    }
  }

  Future<void> _initWithCamera(CameraDescription? camera) async {
    if (mounted) setState(() => _isInitializing = true);

    _macroSub?.cancel();

    try {
      // Dispose controller lama jika sudah initialized
      if (_controller.value.isInitialized) {
        await _controller.dispose();
      }
    } catch (_) {}

    // Buat controller baru jika perlu
    // (Controller bisa di-reuse jika belum disposed)
    try {
      await _controller.initialize(
        options: CameraOptions(
          camera: camera,
          lensDirection: camera?.lensDirection ?? CameraLensDirection.back,
          resolution: ResolutionPreset.high,
          enableAntiMacro: true,
        ),
      );

      _macroSub = _controller.onMacroDetected.listen((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ Anti-macro: Kamera mencoba switch ke macro — diblokir!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      });

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _lastZoom = _controller.value.zoomLevel;
        });
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = '${e.code}: ${e.description}';
        });
      }
    }
  }

  CameraDescription? _findCamera(
    List<CameraDescription> cameras, {
    required CameraLensDirection direction,
    required CameraDeviceType type,
  }) {
    try {
      return cameras.firstWhere(
        (c) => c.lensDirection == direction && c.deviceType == type,
      );
    } catch (_) {
      // Fallback: cari berdasarkan arah saja
      try {
        return cameras.firstWhere((c) => c.lensDirection == direction);
      } catch (_) {
        return cameras.isNotEmpty ? cameras.first : null;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _loadCameras();
    }
  }

  @override
  void dispose() {
    _macroSub?.cancel();
    _controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ──────────────────────────────────────
  // Handlers
  // ──────────────────────────────────────

  Future<void> _takePicture() async {
    try {
      final path = await _controller.takePicture();
      if (!mounted) return;
      setState(() => _lastPhotoPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Foto disimpan: ${path.split('/').last}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on CameraException catch (e) {
      _showError(e.description ?? e.code);
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_controller.value.isRecordingVideo) {
        await _controller.stopVideoRecording();
      } else {
        await _controller.startVideoRecording();
      }
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      _showError(e.description ?? e.code);
    }
  }

  Future<void> _cycleFlashMode() async {
    final next = switch (_controller.value.flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.on,
      FlashMode.on => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    await _controller.setFlashMode(next);
    if (mounted) setState(() {});
  }

  void _handleTapFocus(TapDownDetails details, BoxConstraints constraints) {
    final x = details.localPosition.dx / constraints.maxWidth;
    final y = details.localPosition.dy / constraints.maxHeight;
    _controller.setFocusPoint(x, y);
    _controller.setExposurePoint(x, y);
    setState(() => _focusTapPosition = details.localPosition);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _focusTapPosition = null);
    });
  }

  void _setAspectRatio(double? ratio) {
    setState(() => _selectedAspectRatio = ratio);
    _controller.setAspectRatio(ratio);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $msg'), backgroundColor: Colors.red),
    );
  }

  // ──────────────────────────────────────
  // Build
  // ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Menginisialisasi kamera...',
                style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error: $_errorMessage',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Preview ──────────────────────────
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapDown: (d) => _handleTapFocus(d, constraints),
              onScaleUpdate: (d) {
                final zoom = ((_lastZoom ?? 1.0) * d.scale).clamp(
                  _controller.value.minZoomLevel,
                  _controller.value.maxZoomLevel,
                );
                _controller.setZoomLevel(zoom);
              },
              onScaleEnd: (_) =>
                  setState(() => _lastZoom = _controller.value.zoomLevel),
              child: CameraPreview(
                controller: _controller,
                aspectRatio: _selectedAspectRatio,
              ),
            );
          },
        ),

        // ── Focus Indicator ───────────────────
        if (_focusTapPosition != null)
          Positioned(
            left: _focusTapPosition!.dx - 30,
            top: _focusTapPosition!.dy - 30,
            child: const FocusIndicator(size: 60),
          ),

        // ── Top Bar ───────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Anti-macro badge
                  _StatusBadge(
                    label: 'Anti-Macro',
                    active: _controller.value.antiMacroEnabled,
                    onTap: () async {
                      await _controller.setAntiMacroEnabled(
                          !_controller.value.antiMacroEnabled);
                      setState(() {});
                    },
                  ),

                  // Flash button
                  _FlashButton(
                    mode: _controller.value.flashMode,
                    onTap: _cycleFlashMode,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Zoom + Active Camera info ─────────
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<CameraValue>(
            valueListenable: _controller,
            builder: (_, val, __) {
              final cam = val.activeCamera;
              return Column(
                children: [
                  Text(
                    '${val.zoomLevel.toStringAsFixed(1)}×',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  if (cam != null)
                    Text(
                      cam.name,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                ],
              );
            },
          ),
        ),

        // ── Aspect Ratio Bar ──────────────────
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          child: _AspectRatioBar(
            selected: _selectedAspectRatio,
            onSelect: _setAspectRatio,
          ),
        ),

        // ── Camera Lens Selector ──────────────
        Positioned(
          bottom: 110,
          left: 0,
          right: 0,
          child: _CameraLensSelector(
            cameras: _availableCameras,
            activeCamera: _controller.value.activeCamera,
            onSelect: (cam) => _initWithCamera(cam),
          ),
        ),

        // ── Bottom Controls ───────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _CircleButton(
                    icon: Icons.flip_camera_ios,
                    onTap: () async {
                      await _controller.switchCamera();
                      setState(() {});
                    },
                  ),
                  ValueListenableBuilder<CameraValue>(
                    valueListenable: _controller,
                    builder: (_, val, __) => _CaptureButton(
                      isRecording: val.isRecordingVideo,
                      isTaking: val.isTakingPicture,
                      onTakePicture: _takePicture,
                      onToggleRecord: _toggleRecording,
                    ),
                  ),
                  _LastPhotoThumbnail(path: _lastPhotoPath),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aspect Ratio Bar
// ─────────────────────────────────────────────────────────────────────────────

class _AspectRatioBar extends StatelessWidget {
  const _AspectRatioBar({required this.selected, required this.onSelect});

  final double? selected;
  final ValueChanged<double?> onSelect;

  static const _presets = [
    (label: 'Full', value: null as double?),
    (label: '1:1', value: 1.0),
    (label: '4:3', value: 4 / 3),
    (label: '16:9', value: 16 / 9),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _presets.map((p) {
        final isActive = p.value == selected;
        return GestureDetector(
          onTap: () => onSelect(p.value),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.black45,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: isActive ? Colors.white : Colors.white30),
            ),
            child: Text(
              p.label,
              style: TextStyle(
                color: isActive ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera Lens Selector
// ─────────────────────────────────────────────────────────────────────────────

class _CameraLensSelector extends StatelessWidget {
  const _CameraLensSelector({
    required this.cameras,
    required this.activeCamera,
    required this.onSelect,
  });

  final List<CameraDescription> cameras;
  final CameraDescription? activeCamera;
  final ValueChanged<CameraDescription> onSelect;

  static String _iconLabel(CameraDeviceType type) => switch (type) {
        CameraDeviceType.ultraWide => '0.5×',
        CameraDeviceType.wideAngle => '1×',
        CameraDeviceType.telephoto => '3×',
        CameraDeviceType.trueDepth => 'Front',
        CameraDeviceType.dual => 'Dual',
        CameraDeviceType.dualWide => 'W+',
        CameraDeviceType.triple => 'Pro',
        _ => '?',
      };

  @override
  Widget build(BuildContext context) {
    // Tampilkan hanya kamera belakang (kecuali sedang di front)
    final showFront = activeCamera?.lensDirection == CameraLensDirection.front;
    final filtered = cameras.where((c) {
      if (showFront) return c.lensDirection == CameraLensDirection.front;
      return c.lensDirection == CameraLensDirection.back;
    }).toList();

    if (filtered.length <= 1) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: filtered.map((cam) {
          final isActive = cam == activeCamera;
          return GestureDetector(
            onTap: () => onSelect(cam),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.yellow.withValues(alpha: 0.9)
                    : Colors.black54,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isActive ? Colors.yellow : Colors.white24),
              ),
              child: Text(
                _iconLabel(cam.deviceType),
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Existing widgets (tidak berubah banyak)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              active ? Colors.yellow.withValues(alpha: 0.85) : Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? Colors.yellow : Colors.white30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.shield : Icons.shield_outlined,
                size: 14, color: active ? Colors.black : Colors.white70),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _FlashButton extends StatelessWidget {
  const _FlashButton({required this.mode, required this.onTap});

  final FlashMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (mode) {
      FlashMode.off => (Icons.flash_off, 'OFF'),
      FlashMode.auto => (Icons.flash_auto, 'AUTO'),
      FlashMode.on => (Icons.flash_on, 'ON'),
      FlashMode.torch => (Icons.highlight, 'TORCH'),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: mode == FlashMode.torch
              ? Colors.yellow.withValues(alpha: 0.85)
              : Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: mode == FlashMode.torch ? Colors.black : Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color:
                        mode == FlashMode.torch ? Colors.black : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.isRecording,
    required this.isTaking,
    required this.onTakePicture,
    required this.onToggleRecord,
  });

  final bool isRecording;
  final bool isTaking;
  final VoidCallback onTakePicture;
  final VoidCallback onToggleRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: isTaking ? null : onTakePicture,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              color: isTaking ? Colors.white54 : Colors.white24,
            ),
            child: isTaking
                ? const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2)
                : const SizedBox(),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onToggleRecord,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRecording ? Colors.red : Colors.white30,
              border: Border.all(color: Colors.white54, width: 1.5),
            ),
            child: Icon(isRecording ? Icons.stop : Icons.videocam,
                color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black45,
          border: Border.all(color: Colors.white30),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

class _LastPhotoThumbnail extends StatelessWidget {
  const _LastPhotoThumbnail({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white30),
            color: Colors.black45),
        child: const Icon(Icons.image, color: Colors.white30, size: 24),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _PhotoPreviewScreen(path: path!)),
      ),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 1.5)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.file(File(path!), fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _PhotoPreviewScreen extends StatelessWidget {
  const _PhotoPreviewScreen({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title:
            const Text('Preview Foto', style: TextStyle(color: Colors.white)),
      ),
      body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
    );
  }
}
