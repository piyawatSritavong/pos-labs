import 'dart:convert';
import 'package:frontend/config/api_config.dart';
import 'api_http.dart' as http;

class ApiPartsService {
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

  // GET /parts?limit=&offset=
  static Future<List<Map<String, dynamic>>> getParts({
    required String token,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/parts',
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
        'Failed to load parts: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/parts');
  }

  // GET /parts/search?q=&categoryId=&isActive=&crossBranch=&limit=&offset=
  static Future<List<Map<String, dynamic>>> searchParts({
    required String token,
    String query = '',
    String? categoryId,
    bool? isActive,
    bool? crossBranch,
    int limit = 20,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };

    if (query.isNotEmpty) {
      queryParams['q'] = query;
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      queryParams['categoryId'] = categoryId;
    }
    if (isActive != null) {
      queryParams['isActive'] = isActive.toString();
    }
    if (crossBranch != null) {
      queryParams['crossBranch'] = crossBranch.toString();
    }

    final uri = Uri.parse(
      '$baseUrl/parts/search',
    ).replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to search parts: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/parts/search');
  }

  // GET /parts/:code
  static Future<Map<String, dynamic>> getPartByCode({
    required String token,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/parts/$code');

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch part: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/parts/:code');
  }
}
