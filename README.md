# ios_camera_pro

Plugin Flutter khusus iOS dengan fitur kamera yang lengkap:

- **Anti-Macro Camera** — Mencegah kamera auto-switch ke lensa ultra-wide/macro (iPhone 13 Pro+)
- **Flash Control** — Off / Auto / On / Torch
- **Torch** — Nyalakan senter dengan level brightness yang bisa diatur (0.0–1.0)
- **Zoom** — Optical zoom dengan pinch gesture
- **Tap to Focus** — Fokus ke titik yang diinginkan
- **Tap to Expose** — Exposure ke titik yang diinginkan
- **Exposure Compensation (EV)** — Atur kecerahan manual
- **Photo Capture** — Simpan sebagai JPEG
- **Video Recording** — Simpan sebagai MP4
- **Camera Switch** — Ganti kamera depan/belakang

---

## Instalasi

Tambahkan ke `pubspec.yaml`:

```yaml
dependencies:
  ios_camera_pro:
    path: ../ios_camera_pro  # atau dari pub.dev
```

### iOS — Info.plist

Tambahkan izin berikut di `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Aplikasi ini membutuhkan akses kamera.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Aplikasi ini membutuhkan akses mikrofon untuk merekam video.</string>
```

---

## Penggunaan

### 1. Inisialisasi

```dart
import 'package:ios_camera_pro/ios_camera_pro.dart';

final controller = CameraController();

await controller.initialize(
  options: CameraOptions(
    lensDirection: CameraLensDirection.back,
    resolution: ResolutionPreset.high,
    enableAntiMacro: true, // Aktifkan anti-macro dari awal
  ),
);
```

### 2. Tampilkan Preview

```dart
CameraPreview(controller: controller)
```

### 3. Anti-Macro

```dart
// Toggle anti-macro
await controller.setAntiMacroEnabled(true);

// Listen event macro terdeteksi
controller.onMacroDetected.listen((_) {
  print('Kamera mencoba switch ke macro — diblokir!');
});
```

### 4. Flash & Torch

```dart
// Set mode flash
await controller.setFlashMode(FlashMode.auto);
await controller.setFlashMode(FlashMode.on);
await controller.setFlashMode(FlashMode.off);

// Nyalakan torch (senter) dengan brightness 80%
await controller.setTorchMode(enabled: true, level: 0.8);

// Matikan torch
await controller.setTorchMode(enabled: false);
```

### 5. Zoom

```dart
// Zoom 2x
await controller.setZoomLevel(2.0);

// Batas zoom
final min = controller.value.minZoomLevel;
final max = controller.value.maxZoomLevel;
```

### 6. Focus & Exposure

```dart
// Tap to focus (koordinat normalized 0.0–1.0)
await controller.setFocusPoint(0.5, 0.5); // tengah layar

// Tap to expose
await controller.setExposurePoint(0.5, 0.5);

// Exposure compensation
await controller.setExposureCompensation(1.0); // +1 EV (lebih terang)
await controller.setExposureCompensation(-1.0); // -1 EV (lebih gelap)
```

### 7. Ambil Foto

```dart
final path = await controller.takePicture();
print('Foto tersimpan di: $path');
```

### 8. Rekam Video

```dart
// Mulai rekam
await controller.startVideoRecording();

// Berhenti rekam
await controller.stopVideoRecording();

// Path video tersimpan via event
controller.cameraEvents.listen((event) {
  if (event.type == CameraEventType.videoRecordingStopped) {
    final path = event.data?['path'];
    print('Video tersimpan di: $path');
  }
});
```

### 9. Ganti Kamera

```dart
await controller.switchCamera();
print(controller.value.lensDirection); // CameraLensDirection.front
```

### 10. Dispose

```dart
@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

---

## CameraValue

`CameraController` extends `ValueNotifier<CameraValue>` sehingga bisa dipakai dengan `ValueListenableBuilder`:

```dart
ValueListenableBuilder<CameraValue>(
  valueListenable: controller,
  builder: (context, value, _) {
    return Text('Zoom: ${value.zoomLevel}x');
  },
);
```

| Field | Tipe | Keterangan |
|---|---|---|
| `isInitialized` | `bool` | Kamera siap |
| `isRecordingVideo` | `bool` | Sedang merekam |
| `isTakingPicture` | `bool` | Sedang capture |
| `flashMode` | `FlashMode` | Mode flash saat ini |
| `isTorchOn` | `bool` | Torch menyala |
| `torchLevel` | `double` | Level torch (0.0–1.0) |
| `zoomLevel` | `double` | Zoom saat ini |
| `minZoomLevel` | `double` | Zoom minimum |
| `maxZoomLevel` | `double` | Zoom maksimum |
| `antiMacroEnabled` | `bool` | Anti-macro aktif |
| `isMacroDetected` | `bool` | Macro pernah terdeteksi |
| `lensDirection` | `CameraLensDirection` | Arah lensa |

---

## Persyaratan

- iOS **14.0+**
- iPhone **13 Pro / 14 Pro / 15 Pro** (atau lebih) untuk fitur anti-macro
- Swift 5.0+
- Flutter 3.10+

---

## Catatan Anti-Macro

Fitur anti-macro bekerja dengan cara:

1. **Selalu menggunakan `builtInWideAngleCamera`** — tidak pernah menggunakan virtual camera (`builtInTripleCamera`, `builtInDualWideCamera`) yang bisa auto-switch ke ultra-wide
2. **iOS 15+**: Menggunakan `setPrimaryConstituentDeviceSwitchingBehavior(.restricted, restrictedSwitchingBehaviorConditions: [])` — ini melarang iOS melakukan konstituen device switching sama sekali
3. **Notifikasi**: Jika iOS masih mencoba switch, event `macroDetected` dikirimkan ke Dart

Pada iPhone lama (bukan Pro atau sebelum 13 Pro), fitur ini otomatis tidak diperlukan dan tidak aktif.
