import 'package:flutter/material.dart';
import 'package:frontend/services/api_branches.dart';

class BranchesProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get branches => _branches;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// โหลดรายการ branches ทั้งหมด
  Future<void> loadBranches({
    required String token,
    bool force = false,
  }) async {
    if (_isLoading) return;
    if (!force && _branches.isNotEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiBranchesService.getBranches(token: token);
      _branches = result;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ดึงข้อมูล branch ตาม ID
  Future<Map<String, dynamic>> getBranchById({
    required String token,
    required String branchId,
  }) async {
    try {
      return await ApiBranchesService.getBranchById(
        token: token,
        branchId: branchId,
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// สร้าง branch ใหม่
  Future<Map<String, dynamic>> createBranch({
    required String token,
    required String branchId,
    required String branchName,
    String? branchNameTh,
    String? address,
    String? addressTh,
    String? phone,
    bool isActive = true,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newBranch = await ApiBranchesService.createBranch(
        token: token,
        branchId: branchId,
        branchName: branchName,
        branchNameTh: branchNameTh,
        address: address,
        addressTh: addressTh,
        phone: phone,
        isActive: isActive,
      );

      // Refresh list after create
      _isLoading = false;
      await loadBranches(token: token, force: true);
      return newBranch;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// อัพเดท branch
  Future<Map<String, dynamic>> updateBranch({
    required String token,
    required String branchId,
    required String branchName,
    String? branchNameTh,
    String? address,
    String? addressTh,
    String? phone,
    bool isActive = true,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedBranch = await ApiBranchesService.updateBranch(
        token: token,
        branchId: branchId,
        branchName: branchName,
        branchNameTh: branchNameTh,
        address: address,
        addressTh: addressTh,
        phone: phone,
        isActive: isActive,
      );

      // Refresh list after update
      _isLoading = false;
      await loadBranches(token: token, force: true);
      return updatedBranch;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// ลบ branch
  Future<void> deleteBranch({
    required String token,
    required String branchId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiBranchesService.deleteBranch(
        token: token,
        branchId: branchId,
      );

      // Refresh list after delete
      _isLoading = false;
      await loadBranches(token: token, force: true);
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Set branches data (สำหรับ sync จาก office_screen)
  void setBranches(List<Map<String, dynamic>> data) {
    _branches = data;
    notifyListeners();
  }

  void clear() {
    _branches = [];
    _error = null;
    notifyListeners();
  }
}
