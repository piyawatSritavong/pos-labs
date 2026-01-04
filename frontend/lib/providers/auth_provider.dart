import 'package:frontend/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  String? _name;
  String? _roleId;
  bool _isLoading = false;

  String? get token => _token;
  String? get name => _name;
  String? get roleId => _roleId;
  bool get isAuthenticated => _token != null;
  bool get isLoading => _isLoading;
  bool get isAdmin => _roleId == 'role.admin';

  // When opening the app, check for existing token
  Future<void> autoLogin() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');

    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      try {
        final me = await ApiService.getCurrentUser(savedToken);
        _name = me['name'] as String?;
        // รองรับทั้ง key แบบ roleId และ role_id จาก API
        _roleId = (me['roleId'] ?? me['role_id']) as String?;
      } catch (_) {
        // ถ้า token ใช้งานไม่ได้ ให้เคลียร์ทิ้ง
        _token = null;
        _name = null;
        _roleId = null;
        await prefs.remove('auth_token');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // Login function
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await ApiService.login(username, password);
      _token = token;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);

      // fetch /auth/me using the token
      try {
        final me = await ApiService.getCurrentUser(token);
        _name = me['name'] as String?;
        // รองรับทั้ง key แบบ roleId และ role_id จาก API
        _roleId = (me['roleId'] ?? me['role_id']) as String?;
      } catch (e) {
        // failed to fetch user info - cleanup and rethrow
        _token = null;
        await prefs.remove('auth_token');
        _isLoading = false;
        notifyListeners();
        rethrow;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Logout function
  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }
}
