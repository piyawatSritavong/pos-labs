import 'package:flutter/material.dart';

import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/auth_storage.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  String? _username;
  String? _name;
  String? _roleId;
  String? _branchId;
  String? _posId;
  String _sessionState = 'active';
  bool _isLoading = false;
  bool _isCustomerDisplay = false;

  String? get token => _token;
  String? get username => _username;
  String? get name => _name;
  String? get roleId => _roleId;
  String? get branchId => _branchId;
  String? get posId => _posId;
  String get sessionState => _sessionState;
  bool get isAuthenticated => _token != null;
  bool get isSessionPending => _sessionState == 'pending';
  bool get isLoading => _isLoading;
  bool get isAdmin => _roleId == 'role.admin';
  bool get isSuperAdmin => _roleId == 'role.admin';
  bool get isHQManager => _roleId == 'role.hq_manager';
  bool get isVanStaff => _roleId == 'role.van_staff';
  bool get isCashier => _roleId == 'role.cashier';
  bool get isPOSOperator => isVanStaff || isCashier;
  bool get hasBackofficeAccess => isSuperAdmin || isHQManager;
  bool get isCustomerDisplay => _isCustomerDisplay;

  Future<void> autoLogin() async {
    _isLoading = true;
    notifyListeners();

    final savedToken = await AuthStorage.read('auth_token');
    final savedIsCustomerDisplay =
        await AuthStorage.read('auth_is_customer_display') == 'true';

    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      _username = await AuthStorage.read('auth_username');
      _name = await AuthStorage.read('auth_name');
      _roleId = await AuthStorage.read('auth_role_id');
      _branchId = await AuthStorage.read('auth_branch_id');
      _posId = await AuthStorage.read('auth_pos_id');
      _sessionState = await AuthStorage.read('auth_session_state') ?? 'active';

      if (savedIsCustomerDisplay) {
        _name = 'Customer Display';
        _roleId = 'role.customer_display';
        _isCustomerDisplay = true;
      } else {
        try {
          final state = await ApiService.getSessionState(savedToken);
          _sessionState = state['state']?.toString() ?? 'active';
          if (_sessionState == 'active') {
            await _loadCurrentUser(savedToken);
          } else if (_sessionState != 'pending') {
            await _clearLocal(notify: false);
          }
        } catch (_) {
          await _clearLocal(notify: false);
        }
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    if (username == 'root' && password == 'root123') {
      _token = 'mock-root-token';
      _username = username;
      _name = 'Customer Display';
      _roleId = 'role.customer_display';
      _sessionState = 'active';
      _isCustomerDisplay = true;
      await _persist();
      _isLoading = false;
      notifyListeners();
      return true;
    }

    try {
      final result = await ApiService.login(username, password);
      _token = result.token;
      _username = username;
      _name = result.name;
      _roleId = result.roleId;
      _sessionState = result.sessionState;
      _isCustomerDisplay = false;

      if (_sessionState == 'active') {
        await _loadCurrentUser(result.token);
      }
      await _persist();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      await _clearLocal(notify: false);
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> refreshCurrentUser() async {
    final currentToken = _token;
    if (currentToken == null) return;
    await _loadCurrentUser(currentToken);
    _sessionState = 'active';
    await _persist();
    notifyListeners();
  }

  Future<void> updateSessionState(String value) async {
    if (_sessionState == value) return;
    _sessionState = value;
    await AuthStorage.write('auth_session_state', value);
    notifyListeners();
  }

  Future<void> logout({bool callBackend = true}) async {
    final currentToken = _token;
    if (callBackend && currentToken != null && currentToken.isNotEmpty) {
      try {
        await ApiService.logout(currentToken);
      } catch (_) {
        // Local logout must still complete when the server is unavailable.
      }
    }
    await _clearLocal();
  }

  Future<void> expireSession() => _clearLocal();

  Future<void> _loadCurrentUser(String currentToken) async {
    final me = await ApiService.getCurrentUser(currentToken);
    _username = (me['username'] as String?) ?? _username;
    _name = me['name'] as String?;
    _roleId = (me['roleId'] ?? me['role_id']) as String?;
    _branchId = me['branchId'] as String?;
    _posId = me['posId'] as String?;
    _isCustomerDisplay = false;
  }

  Future<void> _persist() async {
    final values = <String, String?>{
      'auth_token': _token,
      'auth_username': _username,
      'auth_name': _name,
      'auth_role_id': _roleId,
      'auth_branch_id': _branchId,
      'auth_pos_id': _posId,
      'auth_session_state': _sessionState,
      'auth_is_customer_display': _isCustomerDisplay.toString(),
    };
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null || value.isEmpty) {
        await AuthStorage.remove(entry.key);
      } else {
        await AuthStorage.write(entry.key, value);
      }
    }
  }

  Future<void> _clearLocal({bool notify = true}) async {
    _token = null;
    _username = null;
    _name = null;
    _roleId = null;
    _branchId = null;
    _posId = null;
    _sessionState = 'active';
    _isCustomerDisplay = false;
    await AuthStorage.clearAuth();
    if (notify) notifyListeners();
  }
}
