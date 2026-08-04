import 'package:flutter/material.dart';
import 'package:frontend/services/api_company.dart';
import 'package:frontend/services/app_dialog_service.dart';

class CompanyProvider extends ChangeNotifier {
  Map<String, dynamic>? _company;
  bool _isLoading = false;
  String? _error;

  Map<String, dynamic>? get company => _company;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// โหลดข้อมูล company จาก API
  Future<void> loadCompany({required String token, bool force = false}) async {
    if (_isLoading) return;
    if (!force && _company != null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiCompanyService.getCompany(token: token);
      _company = result;
    } catch (e) {
      _error = AppDialogService.safeMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// อัพเดทข้อมูล company ผ่าน API
  Future<Map<String, dynamic>> updateCompany({
    required String token,
    required String companyName,
    required String companyNameTh,
    required String companyAddress,
    required String companyAddressTh,
    required String phone,
    required String email,
    required String website,
    String? logoUrl,
    required double taxRate,
    required String taxType,
    // Optional — trailing line printed at the bottom of every POS receipt.
    // Null/missing = leave the existing value in DB unchanged.
    String? receiptFooter,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedCompany = await ApiCompanyService.updateCompany(
        token: token,
        companyName: companyName,
        companyNameTh: companyNameTh,
        companyAddress: companyAddress,
        companyAddressTh: companyAddressTh,
        phone: phone,
        email: email,
        website: website,
        logoUrl: logoUrl,
        taxRate: taxRate,
        taxType: taxType,
        receiptFooter: receiptFooter,
      );

      // Refresh data after update
      _isLoading = false;
      await loadCompany(token: token, force: true);
      return updatedCompany;
    } catch (e) {
      _error = AppDialogService.safeMessage(e);
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Set company data (สำหรับ sync จาก office_screen)
  void setCompany(Map<String, dynamic>? data) {
    _company = data;
    notifyListeners();
  }

  void clear() {
    _company = null;
    _error = null;
    notifyListeners();
  }
}
