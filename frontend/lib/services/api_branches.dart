import 'dart:convert';
import 'package:frontend/config/api_config.dart';
import 'package:http/http.dart' as http;

class ApiBranchesService {
  static String get baseUrl => ApiConfig.apiBaseUrl;

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

  // GET /branches - ดึงรายชื่อสาขาทั้งหมด
  static Future<List<Map<String, dynamic>>> getBranches({
    required String token,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/branches',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load branches: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/branches');
  }

  // GET /branches/:id - ดึงข้อมูล branch ตาม ID
  static Future<Map<String, dynamic>> getBranchById({
    required String token,
    required String branchId,
  }) async {
    final uri = Uri.parse('$baseUrl/branches/$branchId');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load branch: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/branches/:id');
  }

  // POST /branches - สร้าง branch ใหม่
  static Future<Map<String, dynamic>> createBranch({
    required String token,
    required String branchId,
    required String branchName,
    String? branchNameTh,
    String? address,
    String? addressTh,
    String? phone,
    bool isActive = true,
  }) async {
    final uri = Uri.parse('$baseUrl/branches');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'branchId': branchId,
        'branchName': branchName,
        'branchNameTh': branchNameTh ?? '',
        'address': address ?? '',
        'addressTh': addressTh ?? '',
        'phone': phone ?? '',
        'isActive': isActive,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create branch: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/branches');
  }

  // PUT /branches/:id - อัพเดท branch
  static Future<Map<String, dynamic>> updateBranch({
    required String token,
    required String branchId,
    required String branchName,
    String? branchNameTh,
    String? address,
    String? addressTh,
    String? phone,
    bool isActive = true,
  }) async {
    final uri = Uri.parse('$baseUrl/branches/$branchId');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'branchName': branchName,
        'branchNameTh': branchNameTh ?? '',
        'address': address ?? '',
        'addressTh': addressTh ?? '',
        'phone': phone ?? '',
        'isActive': isActive,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update branch: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/branches/:id');
  }

  // DELETE /branches/:id - ลบ branch
  static Future<void> deleteBranch({
    required String token,
    required String branchId,
  }) async {
    final uri = Uri.parse('$baseUrl/branches/$branchId');
    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete branch: ${response.statusCode} ${response.body}',
      );
    }
  }
}
