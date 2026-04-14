import 'package:frontend/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  String? _username;
  String? _name;
  String? _roleId;
  String? _branchId;
  String? _posId;
  bool _isLoading = false;
  bool _isCustomerDisplay = false;

  String? get token => _token;
  String? get username => _username;
  String? get name => _name;
  String? get roleId => _roleId;
  String? get branchId => _branchId;
  String? get posId => _posId;
  bool get isAuthenticated => _token != null;
  bool get isLoading => _isLoading;
  bool get isAdmin => _roleId == 'role.admin';
  bool get isSuperAdmin => _roleId == 'role.admin';
  bool get isHQManager => _roleId == 'role.hq_manager';
  bool get isVanStaff => _roleId == 'role.van_staff';
  bool get hasBackofficeAccess => isSuperAdmin || isHQManager;
  bool get isCustomerDisplay => _isCustomerDisplay;

  // When opening the app, check for existing token
  Future<void> autoLogin() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');
    final savedIsCustomerDisplay =
        prefs.getBool('auth_is_customer_display') ?? false;

    if (savedToken != null && savedToken.isNotEmpty) {
      if (savedIsCustomerDisplay) {
        // Restore mock customer-display account without calling API
        _token = savedToken;
        _name = 'Customer Display';
        _roleId = 'role.customer_display';
        _isCustomerDisplay = true;
      } else {
        _token = savedToken;
        try {
          final me = await ApiService.getCurrentUser(savedToken);
          _username = me['username'] as String?;
          _name = me['name'] as String?;
          // รองรับทั้ง key แบบ roleId และ role_id จาก API
          _roleId = (me['roleId'] ?? me['role_id']) as String?;
          _branchId = me['branchId'] as String?;
          _posId = me['posId'] as String?;
          _isCustomerDisplay = false;
        } catch (_) {
          // ถ้า token ใช้งานไม่ได้ ให้เคลียร์ทิ้ง
          _token = null;
          _name = null;
          _roleId = null;
          _branchId = null;
          _posId = null;
          _isCustomerDisplay = false;
          await prefs.remove('auth_token');
          await prefs.remove('auth_is_customer_display');
        }
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // Login function
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    // Mock root account for CustomerScreen
    if (username == 'root' && password == 'root123') {
      _token = 'mock-root-token';
      _name = 'Customer Display';
      _roleId = 'role.customer_display';
      _isCustomerDisplay = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      await prefs.setBool('auth_is_customer_display', true);

      _isLoading = false;
      notifyListeners();
      return true;
    }

    try {
      final token = await ApiService.login(username, password);
      _token = token;
      _username = username;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);

      // fetch /auth/me using the token
      try {
        final me = await ApiService.getCurrentUser(token);
        _username = (me['username'] as String?) ?? username;
        _name = me['name'] as String?;
        _roleId = (me['roleId'] ?? me['role_id']) as String?;
        _branchId = me['branchId'] as String?;
        _posId = me['posId'] as String?;
        _isCustomerDisplay = false;
        await prefs.setBool('auth_is_customer_display', false);
      } catch (e) {
        _token = null;
        _username = null;
        _branchId = null;
        _posId = null;
        _isCustomerDisplay = false;
        await prefs.remove('auth_token');
        await prefs.remove('auth_is_customer_display');
        _isLoading = false;
        notifyListeners();
        rethrow;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _token = null;
      _username = null;
      _name = null;
      _roleId = null;
      _branchId = null;
      _posId = null;
      _isCustomerDisplay = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('auth_is_customer_display');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Logout function
  Future<void> logout() async {
    _token = null;
    _username = null;
    _name = null;
    _roleId = null;
    _branchId = null;
    _posId = null;
    _isCustomerDisplay = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_is_customer_display');
    notifyListeners();
  }
}
