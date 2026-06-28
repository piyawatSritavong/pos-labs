// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class QrPaymentSettingsSection extends StatefulWidget {
  const QrPaymentSettingsSection({super.key});

  @override
  State<QrPaymentSettingsSection> createState() =>
      _QrPaymentSettingsSectionState();
}

class _QrPaymentSettingsSectionState
    extends State<QrPaymentSettingsSection> {
  Uint8List? _qrImage;
  bool _isLoading = false;
  bool _isUploading = false;
  String? _error;

  // POS Staff assignment
  List<Map<String, dynamic>> _vanStaff = [];
  final Set<String> _assignedIds = {};
  bool _isLoadingVanStaff = false;
  bool _isSavingAssignment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQrImage();
      _loadVanStaff();
    });
  }

  Future<void> _loadQrImage() async {
    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) {
      setState(() => _error = 'ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final bytes = await ApiService.getQrImage(token: token);
      if (!mounted) return;
      setState(() => _qrImage = bytes);
    } catch (_) {
      // no QR uploaded yet — not an error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVanStaff() async {
    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) return;
    setState(() => _isLoadingVanStaff = true);
    try {
      final all =
          await ApiService.getUsers(token: token, limit: 200, offset: 0);
      if (!mounted) return;
      setState(() {
        _vanStaff =
            all.where((u) => u['roleId'] == 'role.van_staff').toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingVanStaff = false);
    }
  }

  void _pickAndUploadQr() {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..click();
    input.onChange.listen((event) async {
      final file = input.files?.first;
      if (file == null) return;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoad.listen((_) async {
        final bytes = Uint8List.fromList(
            (reader.result as List<int>).cast<int>());
        final token = context.read<AuthProvider>().token ?? '';
        if (token.isEmpty || !mounted) return;
        setState(() => _isUploading = true);
        try {
          await ApiService.uploadQrImage(
            token: token,
            bytes: bytes,
            contentType: file.type.isNotEmpty ? file.type : 'image/png',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('อัปโหลด QR สำเร็จ')));
          _loadQrImage();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('อัปโหลดไม่สำเร็จ: $e')));
        } finally {
          if (mounted) setState(() => _isUploading = false);
        }
      });
    });
  }

  Future<void> _saveAssignment() async {
    setState(() => _isSavingAssignment = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _isSavingAssignment = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการมอบหมาย QR แล้ว')));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: QR preview + upload
              SizedBox(
                width: 320,
                child: _buildQrPanel(),
              ),
              const SizedBox(width: 24),
              // Right: POS Staff assignment
              Expanded(child: _buildAssignmentPanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrPanel() {
    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'QR โอนเงิน',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'รูป QR ที่แสดงบนหน้าชำระเงิน',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_isLoading || _isUploading)
              const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()))
            else if (_qrImage != null)
              Center(
                child: Image.memory(_qrImage!,
                    width: 200, height: 200, fit: BoxFit.contain),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2_outlined,
                        size: 64, color: AppColors.muted),
                    SizedBox(height: 8),
                    Text('ยังไม่มีรูป QR',
                        style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.danger, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed:
                  (_isUploading || _isLoading) ? null : _pickAndUploadQr,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('อัปโหลด QR ใหม่'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _loadQrImage,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('รีเฟรช'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentPanel() {
    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'มอบหมาย QR ให้ POS Staff',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'เลือก POS Staff ที่จะใช้ QR นี้สำหรับรับชำระเงิน',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_isLoadingVanStaff)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_vanStaff.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                    child: Text('ไม่พบบัญชี POS Staff',
                        style: TextStyle(color: AppColors.muted))),
              )
            else
              Column(
                children: _vanStaff.map((u) {
                  final id = (u['id'] ?? u['username'] ?? '').toString();
                  final name = u['name']?.toString() ?? '';
                  final username = u['username']?.toString() ?? '';
                  final isChecked = _assignedIds.contains(id);
                  return CheckboxListTile(
                    value: isChecked,
                    dense: true,
                    title: Text(name.isNotEmpty ? name : username),
                    subtitle: username.isNotEmpty && name.isNotEmpty
                        ? Text('@$username')
                        : null,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _assignedIds.add(id);
                        } else {
                          _assignedIds.remove(id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSavingAssignment ? null : _saveAssignment,
              child: _isSavingAssignment
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('บันทึกการมอบหมาย'),
            ),
          ],
        ),
      ),
    );
  }
}
