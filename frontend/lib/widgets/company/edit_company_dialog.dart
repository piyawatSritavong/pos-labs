import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/company_provider.dart';
import 'package:provider/provider.dart';

class EditCompanyDialog extends StatefulWidget {
  const EditCompanyDialog({super.key, required this.company});

  final Map<String, dynamic> company;

  @override
  State<EditCompanyDialog> createState() => _EditCompanyDialogState();
}

class _EditCompanyDialogState extends State<EditCompanyDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _companyNameController;
  late TextEditingController _companyNameThController;
  late TextEditingController _companyAddressController;
  late TextEditingController _companyAddressThController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _websiteController;
  late TextEditingController _logoUrlController;
  late TextEditingController _taxRateController;
  late String _taxType;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _companyNameController = TextEditingController(
      text: widget.company['companyName']?.toString() ?? '',
    );
    _companyNameThController = TextEditingController(
      text: widget.company['companyNameTh']?.toString() ?? '',
    );
    _companyAddressController = TextEditingController(
      text: widget.company['companyAddress']?.toString() ?? '',
    );
    _companyAddressThController = TextEditingController(
      text: widget.company['companyAddressTh']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.company['phone']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: widget.company['email']?.toString() ?? '',
    );
    _websiteController = TextEditingController(
      text: widget.company['website']?.toString() ?? '',
    );
    _logoUrlController = TextEditingController(
      text: widget.company['logoUrl']?.toString() ?? '',
    );
    
    // taxRate มาเป็น 0.07 ต้องแปลงเป็น 7
    final taxRate = widget.company['taxRate'];
    double taxRatePercent = 0;
    if (taxRate is num) {
      taxRatePercent = taxRate * 100;
    }
    _taxRateController = TextEditingController(
      text: taxRatePercent.toStringAsFixed(2),
    );
    
    _taxType = widget.company['taxType']?.toString() ?? 'xvat';
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyNameThController.dispose();
    _companyAddressController.dispose();
    _companyAddressThController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _logoUrlController.dispose();
    _taxRateController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final auth = context.read<AuthProvider>();
    final companyProvider = context.read<CompanyProvider>();
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
      // แปลง taxRate จาก % เป็นทศนิยม (7 -> 0.07)
      final taxRatePercent = double.tryParse(_taxRateController.text) ?? 0;
      final taxRate = taxRatePercent / 100;

      await companyProvider.updateCompany(
        token: token,
        companyName: _companyNameController.text.trim(),
        companyNameTh: _companyNameThController.text.trim(),
        companyAddress: _companyAddressController.text.trim(),
        companyAddressTh: _companyAddressThController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        website: _websiteController.text.trim(),
        logoUrl: _logoUrlController.text.trim(),
        taxRate: taxRate,
        taxType: _taxType,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อมูลบริษัทสำเร็จ')),
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
      title: const Text('แก้ไขข้อมูลบริษัท'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ชื่อ (EN)
                TextFormField(
                  controller: _companyNameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อบริษัท (EN) *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณากรอกชื่อบริษัท';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ชื่อ (TH)
                TextFormField(
                  controller: _companyNameThController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อบริษัท (TH) *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณากรอกชื่อบริษัท (ภาษาไทย)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ที่อยู่ (EN)
                TextFormField(
                  controller: _companyAddressController,
                  decoration: const InputDecoration(
                    labelText: 'ที่อยู่ (EN)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // ที่อยู่ (TH)
                TextFormField(
                  controller: _companyAddressThController,
                  decoration: const InputDecoration(
                    labelText: 'ที่อยู่ (TH)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // โทรศัพท์
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'โทรศัพท์',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 16),

                // อีเมล
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'อีเมล',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                // เว็บไซต์
                TextFormField(
                  controller: _websiteController,
                  decoration: const InputDecoration(
                    labelText: 'เว็บไซต์',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.language),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),

                // Logo URL
                TextFormField(
                  controller: _logoUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Logo URL',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.image),
                  ),
                ),
                const SizedBox(height: 16),

                // Tax Rate และ Tax Type
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _taxRateController,
                        decoration: const InputDecoration(
                          labelText: 'อัตราภาษี (%)',
                          border: OutlineInputBorder(),
                          suffixText: '%',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _taxType,
                        decoration: const InputDecoration(
                          labelText: 'ประเภทภาษี',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'xvat',
                            child: Text('xvat (ไม่รวม VAT)'),
                          ),
                          DropdownMenuItem(
                            value: 'vat',
                            child: Text('vat (รวม VAT)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _taxType = value;
                            });
                          }
                        },
                      ),
                    ),
                  ],
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
          onPressed: _isLoading ? null : _handleSave,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}
