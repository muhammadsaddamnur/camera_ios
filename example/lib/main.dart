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

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  final CameraController _controller = CameraController();

  StreamSubscription<CameraEvent>? _macroSub;

  // State UI
  bool _isInitializing = true;
  String? _errorMessage;
  String? _lastPhotoPath;
  double? _lastZoom;

  // Posisi focus indicator
  Offset? _focusTapPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _controller.initialize(
        options: const CameraOptions(
          lensDirection: CameraLensDirection.back,
          resolution: ResolutionPreset.high,
          enableAntiMacro: true, // Anti-macro aktif dari awal
        ),
      );

      // Listen event macro terdeteksi
      _macroSub = _controller.onMacroDetected.listen((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Anti-macro: Kamera mencoba switch ke macro lens — diblokir!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      });

      setState(() {
        _isInitializing = false;
        _lastZoom = _controller.value.zoomLevel;
      });
    } on CameraException catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = '${e.code}: ${e.description}';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
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
        SnackBar(content: Text('Foto disimpan: $path'), duration: const Duration(seconds: 2)),
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
      setState(() {});
    } on CameraException catch (e) {
      _showError(e.description ?? e.code);
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
      setState(() {});
    } on CameraException catch (e) {
      _showError(e.description ?? e.code);
    }
  }

  Future<void> _toggleAntiMacro() async {
    final newValue = !_controller.value.antiMacroEnabled;
    await _controller.setAntiMacroEnabled(newValue);
    setState(() {});
  }

  Future<void> _cycleFlashMode() async {
    final current = _controller.value.flashMode;
    final next = switch (current) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.on,
      FlashMode.on => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    await _controller.setFlashMode(next);
    setState(() {});
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
            Text('Menginisialisasi kamera...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Error: $_errorMessage',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
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
              onTapDown: (details) => _handleTapFocus(details, constraints),
              onScaleUpdate: (details) {
                final zoom = ((_lastZoom ?? 1.0) * details.scale)
                    .clamp(
                      _controller.value.minZoomLevel,
                      _controller.value.maxZoomLevel,
                    );
                _controller.setZoomLevel(zoom);
              },
              onScaleEnd: (_) {
                setState(() => _lastZoom = _controller.value.zoomLevel);
              },
              child: CameraPreview(controller: _controller),
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
                    onTap: _toggleAntiMacro,
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

        // ── Zoom indicator ────────────────────
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: Center(
            child: ValueListenableBuilder<CameraValue>(
              valueListenable: _controller,
              builder: (_, val, __) {
                return Text(
                  '${val.zoomLevel.toStringAsFixed(1)}×',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ),
        ),

        // ── Bottom Controls ───────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Ganti kamera
                  _CircleButton(
                    icon: Icons.flip_camera_ios,
                    onTap: _switchCamera,
                    size: 48,
                  ),

                  // Capture / Stop Recording
                  ValueListenableBuilder<CameraValue>(
                    valueListenable: _controller,
                    builder: (_, val, __) {
                      return _CaptureButton(
                        isRecording: val.isRecordingVideo,
                        isTaking: val.isTakingPicture,
                        onTakePicture: _takePicture,
                        onToggleRecord: _toggleRecording,
                      );
                    },
                  ),

                  // Lihat foto terakhir
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
// Custom Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.active,
    required this.onTap,
  });

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
          color: active ? Colors.yellow.withValues(alpha: 0.85) : Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? Colors.yellow : Colors.white30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.shield : Icons.shield_outlined,
              size: 14,
              color: active ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
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
            Icon(
              icon,
              size: 16,
              color: mode == FlashMode.torch ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: mode == FlashMode.torch ? Colors.black : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
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
        // Tombol foto
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
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : const SizedBox(),
          ),
        ),

        const SizedBox(height: 8),

        // Tombol video
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
            child: Icon(
              isRecording ? Icons.stop : Icons.videocam,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

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
          color: Colors.black45,
        ),
        child: const Icon(Icons.image, color: Colors.white30, size: 24),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _PhotoPreviewScreen(path: path!),
          ),
        );
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.file(File(path!), fit: BoxFit.cover),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo Preview Screen
// ─────────────────────────────────────────────────────────────────────────────

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
        title: const Text('Preview Foto', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}
