import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/company_provider.dart';

class CompanySettingsSection extends StatefulWidget {
  const CompanySettingsSection({super.key});

  @override
  State<CompanySettingsSection> createState() => _CompanySettingsSectionState();
}

class _CompanySettingsSectionState extends State<CompanySettingsSection> {
  final _formKey = GlobalKey<FormState>();

  final _companyNameThController = TextEditingController();
  final _companyNameEnController = TextEditingController();
  final _addressThController = TextEditingController();
  final _addressEnController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _vatRateController = TextEditingController();

  String _taxType = 'xvat';
  String? _logoUrl;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  @override
  void dispose() {
    _companyNameThController.dispose();
    _companyNameEnController.dispose();
    _addressThController.dispose();
    _addressEnController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _vatRateController.dispose();
    super.dispose();
  }

  Future<void> _loadCompany() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage = 'ไม่พบ token กรุณา login ใหม่';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.getCompany(token: token);

      _companyNameThController.text = (data['companyNameTh'] ?? '').toString();
      _companyNameEnController.text = (data['companyName'] ?? '').toString();
      _addressThController.text = (data['companyAddressTh'] ?? '').toString();
      _addressEnController.text = (data['companyAddress'] ?? '').toString();
      _phoneController.text = (data['phone'] ?? '').toString();
      _emailController.text = (data['email'] ?? '').toString();
      _websiteController.text = (data['website'] ?? '').toString();

      final taxRate = data['taxRate'];
      if (taxRate != null) {
        _vatRateController.text = taxRate.toString();
      } else {
        _vatRateController.text = '';
      }

      final taxType = data['taxType'];
      if (taxType is String && taxType.isNotEmpty) {
        _taxType = taxType;
      } else {
        _taxType = 'xvat';
      }

      final logoUrl = data['logoUrl'];
      _logoUrl = (logoUrl is String && logoUrl.isNotEmpty) ? logoUrl : null;
    } catch (e) {
      setState(() {
        _errorMessage = 'โหลดข้อมูลบริษัทไม่สำเร็จ: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveCompany() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบ token กรุณา login ใหม่')),
      );
      return;
    }

    final vatRateText = _vatRateController.text.trim();
    final parsedVat = double.tryParse(vatRateText);
    if (parsedVat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอก VAT Rate เป็นตัวเลข')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ApiService.updateCompany(
        token: token,
        companyName: _companyNameEnController.text.trim(),
        companyNameTh: _companyNameThController.text.trim(),
        companyAddress: _addressEnController.text.trim(),
        companyAddressTh: _addressThController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        website: _websiteController.text.trim(),
        logoUrl: _logoUrl,
        taxRate: parsedVat,
        taxType: _taxType,
      );

      // The POS receipt header reads company info from CompanyProvider (loaded
      // at app startup). Saving here goes straight through ApiService, so the
      // provider's in-memory copy would stay stale and the receipt would keep
      // showing the old name/address until a full reload. Force-refresh it so
      // the edited values appear on the next printed/previewed receipt.
      if (mounted) {
        await context
            .read<CompanyProvider>()
            .loadCompany(token: token, force: true);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลบริษัทสำเร็จ')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'บันทึกข้อมูลไม่สำเร็จ: $e';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกข้อมูลไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editLogoUrl() async {
    final controller = TextEditingController(text: _logoUrl ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ตั้งค่า Logo URL'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Logo URL',
              hintText: 'เช่น https://example.com/logo.png',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() {
        _logoUrl = result.isEmpty ? null : result;
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
              // Top actions row
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _loadCompany,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('รีเฟรชข้อมูล'),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 16),

              // Main card fills remaining height
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(16.0),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.withOpacity(0.4),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _loadCompany,
                                        child: const Text('ลองใหม่'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'ตั้งค่าข้อมูลบริษัท',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'กำหนดชื่อบริษัท ที่อยู่ ข้อมูลติดต่อ และการตั้งค่า VAT เพื่อใช้บนหัวบิล',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 16),

                                        TextFormField(
                                          controller: _companyNameThController,
                                          decoration: const InputDecoration(
                                            labelText: 'ชื่อบริษัท (ไทย)',
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'กรุณากรอกชื่อบริษัท (ไทย)';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _companyNameEnController,
                                          decoration: const InputDecoration(
                                            labelText: 'ชื่อบริษัท (อังกฤษ)',
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'กรุณากรอกชื่อบริษัท (อังกฤษ)';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _addressThController,
                                          decoration: const InputDecoration(
                                            labelText: 'ที่อยู่ (ไทย)',
                                          ),
                                          maxLines: 2,
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _addressEnController,
                                          decoration: const InputDecoration(
                                            labelText: 'ที่อยู่ (อังกฤษ)',
                                          ),
                                          maxLines: 2,
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _phoneController,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'เบอร์โทร',
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextFormField(
                                                controller: _emailController,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Email',
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _websiteController,
                                          decoration: const InputDecoration(
                                            labelText: 'Website',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _vatRateController,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'VAT Rate (%)',
                                                    ),
                                                keyboardType:
                                                    TextInputType.number,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child:
                                                  DropdownButtonFormField<
                                                    String
                                                  >(
                                                    value: _taxType,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: 'Tax Type',
                                                        ),
                                                    items: const [
                                                      DropdownMenuItem(
                                                        value: 'xvat',
                                                        child: Text(
                                                          'ราคานอก VAT (xvat)',
                                                        ),
                                                      ),
                                                      DropdownMenuItem(
                                                        value: 'ivat',
                                                        child: Text(
                                                          'ราคารวม VAT (ivat)',
                                                        ),
                                                      ),
                                                    ],
                                                    onChanged: (value) {
                                                      if (value == null) return;
                                                      setState(() {
                                                        _taxType = value;
                                                      });
                                                    },
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            ElevatedButton.icon(
                                              onPressed: _editLogoUrl,
                                              icon: const Icon(
                                                Icons.image_outlined,
                                              ),
                                              label: const Text(
                                                'ตั้งค่า Logo URL',
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                _logoUrl == null ||
                                                        _logoUrl!.isEmpty
                                                    ? 'ยังไม่ได้ตั้งค่า Logo URL'
                                                    : _logoUrl!,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: _logoUrl == null
                                                      ? AppColors.muted
                                                      : AppColors.text,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            const Spacer(),
                                            ElevatedButton(
                                              onPressed: _isSaving
                                                  ? null
                                                  : _saveCompany,
                                              child: _isSaving
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Text(
                                                      'บันทึกการเปลี่ยนแปลง',
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
