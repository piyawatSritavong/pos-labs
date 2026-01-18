import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiUsersService {
  // ตรวจสอบว่าแอปกำลังรันอยู่ในโหมด Release (Production) หรือไม่
  static const bool _isProduction = bool.fromEnvironment('dart.vm.product');
  static const String baseUrl = _isProduction
      ? 'http://54.169.213.40:8080'
      : 'http://localhost:8080';

  // Helper: ดึง List<Map> จาก response ที่อาจเป็นหลายรูปแบบ
  static List<Map<String, dynamic>> _extractListFromResponse(
    dynamic decoded,
    String endpointName,
  ) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }

    if (decoded is Map<String, dynamic>) {
      // ลองดู key มาตรฐานก่อน
      final listKeys = ['items', 'data', 'users', 'parts', 'results'];
      for (final key in listKeys) {
        if (decoded[key] is List) {
          return (decoded[key] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }

      // ถ้าไม่เจอ ลองหา value แรกที่เป็น List
      final firstListValue = decoded.values.firstWhere(
        (v) => v is List,
        orElse: () => null,
      );

      if (firstListValue is List) {
        return firstListValue.whereType<Map<String, dynamic>>().toList();
      }
    }

    throw Exception('Unexpected $endpointName response format: $decoded');
  }

  // Helper: ดึง Map<String,dynamic> จาก response ที่อาจเป็นหลายรูปแบบ
  static Map<String, dynamic> _extractObjectFromResponse(
    dynamic decoded,
    String endpointName,
  ) {
    if (decoded is Map<String, dynamic>) {
      // ดู field ที่น่าจะห่อ object อยู่
      final objectKeys = ['data', 'bill', 'part', 'result'];
      for (final key in objectKeys) {
        if (decoded[key] is Map<String, dynamic>) {
          return decoded[key] as Map<String, dynamic>;
        }
      }
      // ถ้าไม่มี field พิเศษ ให้คืนทั้ง map เลย
      return decoded;
    }

    if (decoded is List) {
      // ถ้า backend ดันส่งมาเป็น List ให้หยิบตัวแรก
      final first = decoded.firstWhere(
        (e) => e is Map<String, dynamic>,
        orElse: () => null,
      );
      if (first is Map<String, dynamic>) {
        return first;
      }
    }

    throw Exception('Unexpected $endpointName response format: $decoded');
  }

  static Future<List<Map<String, dynamic>>> getUsers({
    required String token,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/users').replace(
      queryParameters: {'limit': '$limit', 'offset': '$offset'},
    );
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load users: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/users');
  }

  static Future<Map<String, dynamic>> getUserById({
    required String token,
    required String userId,
  }) async {
    final uri = Uri.parse('$baseUrl/users/$userId');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load user: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/users/:id');
  }

  static Future<Map<String, dynamic>> createUser({
    required String token,
    required String username,
    required String roleId,
    required String name,
    required String password,
    bool isActive = true,
    bool isSuperuser = false,
  }) async {
    final uri = Uri.parse('$baseUrl/users');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'username': username,
        'roleId': roleId,
        'name': name,
        'password': password,
        'isActive': isActive,
        'isSuperuser': isSuperuser,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create user: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/users');
  }

  static Future<Map<String, dynamic>> updateUser({
    required String token,
    required String userId,
    required String username,
    required String roleId,
    required String name,
    String? password,
    bool? isActive,
    bool? isSuperuser,
  }) async {
    final uri = Uri.parse('$baseUrl/users/$userId');
    final body = <String, dynamic>{
      'username': username,
      'roleId': roleId,
      'name': name,
    };
    if (password != null && password.isNotEmpty) {
      body['password'] = password;
    }
    if (isActive != null) {
      body['isActive'] = isActive;
    }
    if (isSuperuser != null) {
      body['isSuperuser'] = isSuperuser;
    }
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update user: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/users/:id');
  }

  static Future<void> deleteUser({
    required String token,
    required String userId,
  }) async {
    final uri = Uri.parse('$baseUrl/users/$userId');
    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete user: ${response.statusCode} ${response.body}');
    }
  }
}