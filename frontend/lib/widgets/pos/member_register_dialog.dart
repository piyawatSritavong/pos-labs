import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/pos_mirror_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';

class MemberRegisterDialog extends StatefulWidget {
  const MemberRegisterDialog({super.key});

  @override
  State<MemberRegisterDialog> createState() => _MemberRegisterDialogState();
}

class _MemberRegisterDialogState extends State<MemberRegisterDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  Timer? _broadcastTimer;

  bool _isLoading = false;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_scheduleBroadcast);
    _phoneController.addListener(_scheduleBroadcast);
    _emailController.addListener(_scheduleBroadcast);
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    _nameController.removeListener(_scheduleBroadcast);
    _phoneController.removeListener(_scheduleBroadcast);
    _emailController.removeListener(_scheduleBroadcast);
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    PosMirrorService.current?.notifyDialogState(null);
    super.dispose();
  }

  void _scheduleBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer(const Duration(milliseconds: 300), _broadcastState);
  }

  void _broadcastState() {
    PosMirrorService.current?.notifyDialogState({
      'type': 'member_register',
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': _emailController.text.trim(),
      'stage': _success ? 'success' : (_error != null ? 'error' : 'filling'),
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ApiService.createMember(
        token: token,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _success = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _success ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ลงทะเบียนสมาชิก',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'ชื่อ *',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'เบอร์โทร *',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'กรุณากรอกเบอร์โทร' : null,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'อีเมล (ไม่บังคับ)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _isLoading ? null : () => Navigator.of(context).pop(),
                child: const Text('ยกเลิก'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('ลงทะเบียน'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline,
            color: Colors.green, size: 56),
        const SizedBox(height: 12),
        Text(
          'ลงทะเบียนสมาชิก "${_nameController.text.trim()}" สำเร็จ',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}
