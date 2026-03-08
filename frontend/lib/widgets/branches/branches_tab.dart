import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/branches_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/branches/create_branch_dialog.dart';
import 'package:provider/provider.dart';

class BranchesTab extends StatefulWidget {
  const BranchesTab({super.key, this.data});

  final List<Map<String, dynamic>>? data;

  @override
  State<BranchesTab> createState() => _BranchesTabState();
}

class _BranchesTabState extends State<BranchesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBranchesIfNeeded();
    });
  }

  Future<void> _loadBranchesIfNeeded() async {
    final auth = context.read<AuthProvider>();
    final branchesProvider = context.read<BranchesProvider>();
    final token = auth.token;
    if (token == null) return;

    if (branchesProvider.branches.isEmpty) {
      await branchesProvider.loadBranches(token: token);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getBranchesFromProvider(BranchesProvider branchesProvider) {
    if (branchesProvider.branches.isNotEmpty) {
      return branchesProvider.branches;
    }
    if (widget.data != null && widget.data!.isNotEmpty) {
      return widget.data!;
    }
    return [];
  }

  List<Map<String, dynamic>> _getFilteredBranches(BranchesProvider branchesProvider) {
    final branches = _getBranchesFromProvider(branchesProvider);
    if (_searchQuery.isEmpty) return branches;
    return branches.where((branch) {
      final name = (branch['branchName']?.toString() ?? '').toLowerCase();
      final nameTh = (branch['branchNameTh']?.toString() ?? '').toLowerCase();
      final branchId = (branch['branchId']?.toString() ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          nameTh.contains(_searchQuery) ||
          branchId.contains(_searchQuery);
    }).toList();
  }

  Future<void> _handleAddBranch() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CreateBranchDialog(),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _handleUpdate(Map<String, dynamic> branch) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditBranchDialog(branch: branch),
    );

    if (result != null && mounted) {
      final auth = context.read<AuthProvider>();
      final branchesProvider = context.read<BranchesProvider>();
      final token = auth.token;
      if (token == null) return;

      try {
        await branchesProvider.updateBranch(
          token: token,
          branchId: branch['branchId']?.toString() ?? '',
          branchName: result['branchName'] ?? '',
          branchNameTh: result['branchNameTh'],
          address: result['address'],
          addressTh: result['addressTh'],
          phone: result['phone'],
          isActive: result['isActive'] ?? true,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('อัพเดทสาขาสำเร็จ')),
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
      }
    }
  }

  Future<void> _handleDelete(Map<String, dynamic> branch) async {
    final branchName = branch['branchNameTh']?.toString() ??
        branch['branchName']?.toString() ??
        'ไม่ทราบชื่อ';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบสาขา "$branchName" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final auth = context.read<AuthProvider>();
      final branchesProvider = context.read<BranchesProvider>();
      final token = auth.token;
      if (token == null) return;

      try {
        await branchesProvider.deleteBranch(
          token: token,
          branchId: branch['branchId']?.toString() ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ลบสาขาสำเร็จ')),
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BranchesProvider>(
      builder: (context, branchesProvider, _) {
        final filteredBranches = _getFilteredBranches(branchesProvider);

        if (branchesProvider.isLoading &&
            branchesProvider.branches.isEmpty &&
            (widget.data == null || widget.data!.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ข้อมูลสาขา',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _handleAddBranch,
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มสาขา'),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'ค้นหาสาขา...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),

            // Branch Cards Grid
            filteredBranches.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'ไม่พบข้อมูลสาขา',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.35,
                    ),
                    itemCount: filteredBranches.length,
                    itemBuilder: (context, index) {
                      final branch = filteredBranches[index];
                      return _BranchCard(
                        branch: branch,
                        onUpdate: () => _handleUpdate(branch),
                        onDelete: () => _handleDelete(branch),
                      );
                    },
                  ),
          ],
        );
      },
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.onUpdate,
    required this.onDelete,
  });

  final Map<String, dynamic> branch;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final branchId = branch['branchId']?.toString() ?? '-';
    final branchName = branch['branchNameTh']?.toString() ??
        branch['branchName']?.toString() ??
        'ไม่ทราบชื่อ';
    final branchNameEn = branch['branchName']?.toString() ?? '';
    final address = branch['addressTh']?.toString() ??
        branch['address']?.toString() ??
        '-';
    final phone = branch['phone']?.toString() ?? '-';
    final isActive = branch['isActive'] != false;

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon + ID + Badge
            Row(
              children: [
                // Store Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.store_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Branch ID
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.muted.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$branchId',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
                // Active Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'เปิด' : 'ปิด',
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive ? Colors.green[700] : Colors.red[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Branch Name
            Text(
              branchName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (branchNameEn.isNotEmpty && branchNameEn != branchName)
              Text(
                branchNameEn,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

            const SizedBox(height: 8),

            // Address + Phone
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onUpdate,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('แก้ไข'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ลบ'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditBranchDialog extends StatefulWidget {
  const _EditBranchDialog({required this.branch});

  final Map<String, dynamic> branch;

  @override
  State<_EditBranchDialog> createState() => _EditBranchDialogState();
}

class _EditBranchDialogState extends State<_EditBranchDialog> {
  late TextEditingController _branchNameController;
  late TextEditingController _branchNameThController;
  late TextEditingController _addressController;
  late TextEditingController _addressThController;
  late TextEditingController _phoneController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _branchNameController = TextEditingController(
      text: widget.branch['branchName']?.toString() ?? '',
    );
    _branchNameThController = TextEditingController(
      text: widget.branch['branchNameTh']?.toString() ?? '',
    );
    _addressController = TextEditingController(
      text: widget.branch['address']?.toString() ?? '',
    );
    _addressThController = TextEditingController(
      text: widget.branch['addressTh']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.branch['phone']?.toString() ?? '',
    );
    _isActive = widget.branch['isActive'] != false;
  }

  @override
  void dispose() {
    _branchNameController.dispose();
    _branchNameThController.dispose();
    _addressController.dispose();
    _addressThController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchId = widget.branch['branchId']?.toString() ?? '-';

    return AlertDialog(
      title: Text('แก้ไขสาขา #$branchId'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _branchNameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อสาขา (EN)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _branchNameThController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อสาขา (TH)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'ที่อยู่ (EN)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _addressThController,
                decoration: const InputDecoration(
                  labelText: 'ที่อยู่ (TH)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'โทรศัพท์',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('เปิดใช้งาน'),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'branchName': _branchNameController.text,
              'branchNameTh': _branchNameThController.text,
              'address': _addressController.text,
              'addressTh': _addressThController.text,
              'phone': _phoneController.text,
              'isActive': _isActive,
            });
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
