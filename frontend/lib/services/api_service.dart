import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:8080';

  static Future<String> login(String username, String password) async {
    final uri = Uri.parse('$baseUrl/auth/login');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'branchId': '00000',
        'posId': 'POS001',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Login failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    // พยายามดึง token แบบยืดหยุ่น
    if (decoded is Map<String, dynamic>) {
      if (decoded['token'] is String) {
        return decoded['token'] as String;
      }
      if (decoded['data'] is Map<String, dynamic> &&
          (decoded['data'] as Map<String, dynamic>)['token'] is String) {
        return (decoded['data'] as Map<String, dynamic>)['token'] as String;
      }
    }

    throw Exception('Unexpected /auth/login response format: ${response.body}');
  }

  static Future<Map<String, dynamic>> getCurrentUser(String token) async {
    final uri = Uri.parse('$baseUrl/auth/me');

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch current user: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      // รองรับ { ...userFields } หรือ { data: { ...userFields } }
      if (decoded['data'] is Map<String, dynamic>) {
        return decoded['data'] as Map<String, dynamic>;
      }
      return decoded;
    }

    throw Exception('Unexpected /auth/me response format: ${response.body}');
  }
}
