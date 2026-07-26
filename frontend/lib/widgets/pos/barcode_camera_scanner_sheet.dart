import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/pos_error_message.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeCameraScannerSheet extends StatefulWidget {
  const BarcodeCameraScannerSheet({
    super.key,
    required this.onBarcode,
    this.cooldown = const Duration(milliseconds: 1500),
  });

  final Future<void> Function(String barcode) onBarcode;
  final Duration cooldown;

  @override
  State<BarcodeCameraScannerSheet> createState() =>
      _BarcodeCameraScannerSheetState();
}

class _BarcodeCameraScannerSheetState extends State<BarcodeCameraScannerSheet> {
  late final MobileScannerController _controller;
  final List<String> _queue = [];
  final Map<String, DateTime> _lastAcceptedAt = {};
  bool _isProcessing = false;
  int _acceptedCount = 0;
  String? _lastBarcode;
  String? _statusMessage;
  String? _errorMessage;

  static const _formats = <BarcodeFormat>[
    BarcodeFormat.code128,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.itf2of5,
    BarcodeFormat.itf2of5WithChecksum,
    BarcodeFormat.itf14,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.codabar,
  ];

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 250,
      formats: _formats,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? barcode.displayValue;
      final code = raw?.trim().toUpperCase();
      if (code == null || code.isEmpty) continue;
      if (!_acceptBarcode(code)) continue;
      _queue.add(code);
      _lastBarcode = code;
      _errorMessage = null;
      _statusMessage = 'รอเพิ่มสินค้า $code';
      setState(() {});
      _processQueue();
      break;
    }
  }

  bool _acceptBarcode(String code) {
    final now = DateTime.now();
    final last = _lastAcceptedAt[code];
    if (last != null && now.difference(last) < widget.cooldown) {
      return false;
    }
    _lastAcceptedAt[code] = now;
    return true;
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    while (_queue.isNotEmpty && mounted) {
      final code = _queue.removeAt(0);
      setState(() {
        _statusMessage = 'กำลังเพิ่มสินค้า $code';
      });
      try {
        await widget.onBarcode(code);
        if (!mounted) return;
        setState(() {
          _acceptedCount++;
          _statusMessage = 'เพิ่มสินค้าแล้ว $code';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'เพิ่มสินค้าไม่สำเร็จ: ${posErrorMessage(e)}';
          _statusMessage = 'สแกนต่อได้ หรือพิมพ์บาร์โค้ดแทน';
        });
      }
    }
    _isProcessing = false;
    if (mounted) setState(() {});
  }

  String _cameraErrorMessage(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'ไม่ได้รับอนุญาตให้ใช้กล้อง กรุณาอนุญาตกล้องใน browser แล้วลองใหม่',
      MobileScannerErrorCode.unsupported =>
        'browser หรืออุปกรณ์นี้ไม่รองรับการสแกนผ่านกล้อง',
      _ =>
        error.errorDetails?.message ??
            'เปิดกล้องไม่ได้ กรุณาลองใหม่หรือพิมพ์บาร์โค้ดแทน',
    };
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Material(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: MobileScanner(
                controller: _controller,
                fit: BoxFit.cover,
                onDetect: _handleDetection,
                errorBuilder: (context, error) {
                  final message = _cameraErrorMessage(error);
                  return _ScannerErrorPanel(
                    message: message,
                    onClose: () => Navigator.of(context).maybePop(),
                  );
                },
                placeholderBuilder: (context) {
                  return const ColoredBox(
                    color: Colors.black,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),
            Positioned.fill(child: IgnorePointer(child: _ScanFrameOverlay())),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: _ScannerTopBar(onClose: () => Navigator.of(context).pop()),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10 + bottomPadding,
              child: _ScannerStatusPanel(
                lastBarcode: _lastBarcode,
                statusMessage: _statusMessage,
                errorMessage: _errorMessage,
                queueCount: _queue.length,
                isProcessing: _isProcessing,
                acceptedCount: _acceptedCount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerTopBar extends StatelessWidget {
  const _ScannerTopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'เล็งกรอบไปที่บาร์โค้ดสินค้า',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.58),
            foregroundColor: Colors.white,
          ),
          onPressed: onClose,
          icon: const Icon(Icons.close),
          tooltip: 'ปิดกล้อง',
        ),
      ],
    );
  }
}

class _ScanFrameOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ScanFramePainter());
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = size.width * 0.78;
    final frameHeight = frameWidth * 0.42;
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: frameWidth,
      height: frameHeight,
    );
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.32);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(18)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, scrim);

    final border = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final corner = frame.width * 0.13;
    final radius = 18.0;
    final points = <Path>[
      Path()
        ..moveTo(frame.left, frame.top + radius + corner)
        ..lineTo(frame.left, frame.top + radius)
        ..quadraticBezierTo(
          frame.left,
          frame.top,
          frame.left + radius,
          frame.top,
        )
        ..lineTo(frame.left + radius + corner, frame.top),
      Path()
        ..moveTo(frame.right - radius - corner, frame.top)
        ..lineTo(frame.right - radius, frame.top)
        ..quadraticBezierTo(
          frame.right,
          frame.top,
          frame.right,
          frame.top + radius,
        )
        ..lineTo(frame.right, frame.top + radius + corner),
      Path()
        ..moveTo(frame.right, frame.bottom - radius - corner)
        ..lineTo(frame.right, frame.bottom - radius)
        ..quadraticBezierTo(
          frame.right,
          frame.bottom,
          frame.right - radius,
          frame.bottom,
        )
        ..lineTo(frame.right - radius - corner, frame.bottom),
      Path()
        ..moveTo(frame.left + radius + corner, frame.bottom)
        ..lineTo(frame.left + radius, frame.bottom)
        ..quadraticBezierTo(
          frame.left,
          frame.bottom,
          frame.left,
          frame.bottom - radius,
        )
        ..lineTo(frame.left, frame.bottom - radius - corner),
    ];
    for (final point in points) {
      canvas.drawPath(point, border);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScannerStatusPanel extends StatelessWidget {
  const _ScannerStatusPanel({
    required this.lastBarcode,
    required this.statusMessage,
    required this.errorMessage,
    required this.queueCount,
    required this.isProcessing,
    required this.acceptedCount,
  });

  final String? lastBarcode;
  final String? statusMessage;
  final String? errorMessage;
  final int queueCount;
  final bool isProcessing;
  final int acceptedCount;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage ?? statusMessage ?? 'พร้อมสแกนต่อเนื่อง';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                errorMessage == null ? Icons.qr_code_scanner : Icons.error,
                color: errorMessage == null
                    ? AppColors.accent
                    : AppColors.danger,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  lastBarcode == null
                      ? 'ยังไม่พบบาร์โค้ด'
                      : 'ล่าสุด: $lastBarcode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Text(
                'เพิ่มแล้ว $acceptedCount',
                style: const TextStyle(color: Colors.white70),
              ),
              if (queueCount > 0 || isProcessing) ...[
                const SizedBox(width: 8),
                Text(
                  'คิว $queueCount',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScannerErrorPanel extends StatelessWidget {
  const _ScannerErrorPanel({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.white, size: 42),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onClose,
                icon: const Icon(Icons.keyboard),
                label: const Text('พิมพ์บาร์โค้ดแทน'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
