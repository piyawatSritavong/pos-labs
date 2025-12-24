import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';

class UsersProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get users => List.unmodifiable(_users);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadUsers({
    required String token,
    int limit = 100,
    int offset = 0,
    bool force = false,
  }) async {
    if (_isLoading) return;
    if (!force && _users.isNotEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await ApiService.getUsers(
        token: token,
        limit: limit,
        offset: offset,
      );
      _users = results;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> getUserById({
    required String token,
    required String userId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await ApiService.getUserById(token: token, userId: userId);
      return user;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createUser({
    required String token,
    required String username,
    required String roleId,
    required String name,
    required String password,
    bool isActive = true,
    bool isSuperuser = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newUser = await ApiService.createUser(
        token: token,
        username: username,
        roleId: roleId,
        name: name,
        password: password,
        isActive: isActive,
        isSuperuser: isSuperuser,
      );
      // Refresh list after creating - ต้อง reset isLoading ก่อนเรียก loadUsers
      _isLoading = false;
      await loadUsers(token: token, force: true);
      return newUser;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateUser({
    required String token,
    required String userId,
    required String username,
    required String roleId,
    required String name,
    String? password,
    bool? isActive,
    bool? isSuperuser,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedUser = await ApiService.updateUser(
        token: token,
        userId: userId,
        username: username,
        roleId: roleId,
        name: name,
        password: password,
        isActive: isActive,
        isSuperuser: isSuperuser,
      );
      // Update in local list if exists
      final index = _users.indexWhere((u) => u['id']?.toString() == userId);
      if (index != -1) {
        _users[index] = updatedUser;
      }
      // Refresh list to ensure consistency - ต้อง reset isLoading ก่อนเรียก loadUsers
      _isLoading = false;
      await loadUsers(token: token, force: true);
      return updatedUser;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteUser({
    required String token,
    required String userId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.deleteUser(token: token, userId: userId);
      // Remove from local list
      _users.removeWhere((u) => u['id']?.toString() == userId);
      // Refresh list to ensure consistency - ต้อง reset isLoading ก่อนเรียก loadUsers
      _isLoading = false;
      await loadUsers(token: token, force: true);
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  void clear() {
    _users = [];
    _error = null;
    notifyListeners();
  }
}

