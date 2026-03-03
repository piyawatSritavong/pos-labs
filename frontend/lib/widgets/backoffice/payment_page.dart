import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class QrPaymentSettingsSection extends StatefulWidget {
  const QrPaymentSettingsSection({super.key});

  @override
  State<QrPaymentSettingsSection> createState() => _QrPaymentSettingsSectionState();
}

class _QrPaymentSettingsSectionState extends State<QrPaymentSettingsSection> {
  Uint8List? _qrImage;
  bool _isLoading = false;
  String? _error;

  Future<void> _loadQrImage() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token ?? '';

    if (token.isEmpty) {
      setState(() {
        _error = 'ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bytes = await ApiService.getQrImage(token: token);
      if (!mounted) return;
      setState(() {
        _qrImage = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'โหลด QR ไม่สำเร็จ: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Actions row
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _loadQrImage,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('โหลด QR สำหรับหน้าชำระเงิน'),
                  ),
                  const SizedBox(width: 8),
                  if (_isLoading)
                    const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 16),

              // Main card with centered QR / placeholder
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_qrImage != null)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'ตัวอย่าง QR สำหรับหน้าชำระเงิน',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Image.memory(
                                    _qrImage!,
                                    width: 220,
                                    height: 220,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.qr_code_2_outlined,
                                size: 72,
                                color: AppColors.muted,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'ยังไม่มี QR โหลดขึ้นมา',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'กดปุ่มด้านบนเพื่อโหลดรูป QR จากระบบ',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}