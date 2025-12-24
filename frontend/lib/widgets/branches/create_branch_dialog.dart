import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/branches_provider.dart';
import 'package:provider/provider.dart';

class CreateBranchDialog extends StatefulWidget {
  const CreateBranchDialog({super.key});

  @override
  State<CreateBranchDialog> createState() => _CreateBranchDialogState();
}

class _CreateBranchDialogState extends State<CreateBranchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _branchIdController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchNameThController = TextEditingController();
  final _addressController = TextEditingController();
  final _addressThController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _branchIdController.dispose();
    _branchNameController.dispose();
    _branchNameThController.dispose();
    _addressController.dispose();
    _addressThController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final auth = context.read<AuthProvider>();
    final branchesProvider = context.read<BranchesProvider>();
    final token = auth.token;

    if (token == null) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่พบ token กรุณาเข้าสู่ระบบใหม่'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      await branchesProvider.createBranch(
        token: token,
        branchId: _branchIdController.text.trim(),
        branchName: _branchNameController.text.trim(),
        branchNameTh: _branchNameThController.text.trim(),
        address: _addressController.text.trim(),
        addressTh: _addressThController.text.trim(),
        phone: _phoneController.text.trim(),
        isActive: _isActive,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สร้างสาขาสำเร็จ')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เพิ่มสาขาใหม่'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branch ID
                TextFormField(
                  controller: _branchIdController,
                  decoration: const InputDecoration(
                    labelText: 'รหัสสาขา *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tag),
                    hintText: 'เช่น 00001, BRANCH001',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณากรอกรหัสสาขา';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Branch Name (EN)
                TextFormField(
                  controller: _branchNameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อสาขา (EN) *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณากรอกชื่อสาขา';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Branch Name (TH)
                TextFormField(
                  controller: _branchNameThController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อสาขา (TH)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                ),
                const SizedBox(height: 16),

                // Address (EN)
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'ที่อยู่ (EN)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Address (TH)
                TextFormField(
                  controller: _addressThController,
                  decoration: const InputDecoration(
                    labelText: 'ที่อยู่ (TH)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'โทรศัพท์',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 16),

                // Active switch
                SwitchListTile(
                  title: const Text('เปิดใช้งาน'),
                  subtitle: Text(
                    _isActive ? 'สาขาพร้อมใช้งาน' : 'สาขาถูกปิดใช้งาน',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleCreate,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('สร้างสาขา'),
        ),
      ],
    );
  }
}
