import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'camera_controller.dart';
import 'camera_value.dart';

/// Widget preview kamera.
///
/// Harus dipasang setelah [CameraController.initialize()] berhasil.
///
/// Contoh:
/// ```dart
/// if (controller.value.isInitialized)
///   CameraPreview(controller: controller)
/// ```
class CameraPreview extends StatelessWidget {
  const CameraPreview({
    super.key,
    required this.controller,
    this.child,
  });

  final CameraController controller;

  /// Widget yang di-overlay di atas preview kamera (opsional).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) {
          return const ColoredBox(color: Color(0xFF000000));
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            const UiKitView(
              viewType: 'ios_camera_pro/preview',
              creationParamsCodec: StandardMessageCodec(),
            ),
            if (child != null) child!,
          ],
        );
      },
    );
  }
}

/// Widget focus indicator yang muncul saat user tap untuk fokus.
class FocusIndicator extends StatefulWidget {
  const FocusIndicator({
    super.key,
    this.size = 60.0,
    this.color = const Color(0xFFFFD700),
    this.strokeWidth = 1.5,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  State<FocusIndicator> createState() => _FocusIndicatorState();
}

class _FocusIndicatorState extends State<FocusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 1.4, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _FocusPainter(
                  color: widget.color,
                  strokeWidth: widget.strokeWidth,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusPainter extends CustomPainter {
  _FocusPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    const cornerLength = 10.0;
    final w = size.width;
    final h = size.height;

    // Pojok kiri atas
    canvas.drawLine(const Offset(0, cornerLength), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(cornerLength, 0), paint);

    // Pojok kanan atas
    canvas.drawLine(Offset(w - cornerLength, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, cornerLength), paint);

    // Pojok kanan bawah
    canvas.drawLine(Offset(w, h - cornerLength), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w - cornerLength, h), paint);

    // Pojok kiri bawah
    canvas.drawLine(Offset(cornerLength, h), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant _FocusPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
