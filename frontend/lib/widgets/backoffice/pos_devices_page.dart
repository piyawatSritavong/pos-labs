import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:provider/provider.dart';

class PosManagementSection extends StatefulWidget {
  const PosManagementSection({super.key});

  @override
  State<PosManagementSection> createState() => _PosManagementSectionState();
}

class _PosManagementSectionState extends State<PosManagementSection> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _vanStaff = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final all = await ApiService.getUsers(token: token, limit: 200, offset: 0);
      setState(() {
        _vanStaff = all
            .where((u) => u['roleId'] == 'role.van_staff')
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
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
              Row(
                children: [
                  const Text(
                    'Van Staff',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${_vanStaff.length} คน)',
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'รีเฟรช',
                    onPressed: _isLoading ? null : _load,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppColors.danger, size: 40),
                                const SizedBox(height: 12),
                                Text(_error!,
                                    style: const TextStyle(
                                        color: AppColors.danger)),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                    onPressed: _load,
                                    child: const Text('ลองใหม่')),
                              ],
                            ),
                          )
                        : _vanStaff.isEmpty
                            ? const Center(
                                child: Text(
                                  'ไม่มีบัญชี Van Staff',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                              )
                            : SingleChildScrollView(
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: _vanStaff
                                      .map((u) => _VanStaffCard(user: u))
                                      .toList(),
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

class _VanStaffCard extends StatelessWidget {
  const _VanStaffCard({required this.user});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final name = user['name']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final branchId = user['branchId']?.toString() ?? '';
    final isActive = user['isActive'] != false;

    return SizedBox(
      width: 220,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    child: const Icon(Icons.local_shipping_outlined,
                        color: AppColors.primary, size: 20),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: isActive ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive
                              ? Colors.green.shade700
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                name.isNotEmpty ? name : username,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (username.isNotEmpty)
                Text(
                  '@$username',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (branchId.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.store_outlined,
                        size: 13, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        branchId,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
