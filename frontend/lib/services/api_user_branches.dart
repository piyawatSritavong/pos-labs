import 'dart:convert';
import 'package:frontend/config/api_config.dart';
import 'api_http.dart' as http;

class ApiUserBranchesService {
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

  // GET /user-branches
  static Future<List<Map<String, dynamic>>> getUserBranches({
    required String token,
    String? userId,
    String? branchId,
  }) async {
    late Uri uri;
    if (userId != null && branchId != null) {
      uri = Uri.parse('$baseUrl/user-branches/$userId/$branchId');
    } else if (userId != null) {
      uri = Uri.parse('$baseUrl/user-branches/user/$userId');
    } else if (branchId != null) {
      uri = Uri.parse('$baseUrl/user-branches/branch/$branchId');
    } else {
      throw Exception('getUserBranches requires userId or branchId');
    }

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load user branches: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/user-branches');
  }
}
