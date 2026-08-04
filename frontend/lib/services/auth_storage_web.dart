// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

class AuthStorage {
  static Future<String?> read(String key) async =>
      html.window.sessionStorage[key];

  static Future<void> write(String key, String value) async {
    html.window.sessionStorage[key] = value;
  }

  static Future<void> remove(String key) async {
    html.window.sessionStorage.remove(key);
  }

  static Future<void> clearAuth() async {
    for (final key in authStorageKeys) {
      html.window.sessionStorage.remove(key);
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
