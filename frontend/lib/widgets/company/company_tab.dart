import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/company_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/company/edit_company_dialog.dart';
import 'package:provider/provider.dart';

class CompanyTab extends StatefulWidget {
  const CompanyTab({super.key, this.data});

  final Map<String, dynamic>? data;

  @override
  State<CompanyTab> createState() => _CompanyTabState();
}

class _CompanyTabState extends State<CompanyTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCompanyIfNeeded();
    });
  }

  Future<void> _loadCompanyIfNeeded() async {
    final auth = context.read<AuthProvider>();
    final companyProvider = context.read<CompanyProvider>();
    final token = auth.token;
    if (token == null) return;

    if (companyProvider.company == null) {
      await companyProvider.loadCompany(token: token);
    }
  }

  Map<String, dynamic>? _getCompany(CompanyProvider companyProvider) {
    // ใช้ CompanyProvider เป็นหลัก
    if (companyProvider.company != null) {
      return companyProvider.company;
    }
    // Fallback to widget.data
    return widget.data;
  }

  Future<void> _handleEdit(Map<String, dynamic> company) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditCompanyDialog(company: company),
    );

    // Dialog returns true when company was updated successfully
    if (result == true && mounted) {
      setState(() {}); // Trigger rebuild
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CompanyProvider>(
      builder: (context, companyProvider, _) {
        final company = _getCompany(companyProvider);

        if (companyProvider.isLoading && company == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return _SectionContainer(
          title: 'Company Settings',
          trailing: company != null
              ? IconButton(
                  onPressed: () => _handleEdit(company),
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'แก้ไข',
                )
              : null,
          child: company == null
              ? const _EmptyMessage(message: 'ไม่พบข้อมูลบริษัท')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow(label: 'ชื่อ (TH)', value: company['companyNameTh']),
                    _DetailRow(label: 'ชื่อ (EN)', value: company['companyName']),
                    _DetailRow(label: 'ที่อยู่ (TH)', value: company['companyAddressTh']),
                    _DetailRow(label: 'ที่อยู่ (EN)', value: company['companyAddress']),
                    _DetailRow(label: 'โทรศัพท์', value: company['phone']),
                    _DetailRow(label: 'อีเมล', value: company['email']),
                    _DetailRow(label: 'เว็บไซต์', value: company['website']),
                    _DetailRow(
                      label: 'ประเภทภาษี',
                      value:
                          '${company['taxType'] ?? '-'} (${((company['taxRate'] ?? 0) * 100).toStringAsFixed(2)}%)',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _SectionContainer extends StatelessWidget {
  const _SectionContainer({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '-',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: const TextStyle(color: AppColors.muted)),
    );
  }
}
