import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in authStorageKeys) {
      await prefs.remove(key);
    }
  }
}

const authStorageKeys = <String>[
  'auth_token',
  'auth_username',
  'auth_name',
  'auth_role_id',
  'auth_branch_id',
  'auth_pos_id',
  'auth_session_state',
  'auth_is_customer_display',
];
