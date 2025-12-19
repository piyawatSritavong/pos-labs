import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:8080';

  // ====================== Auth ======================

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

  // ====================== Parts (สินค้า) ======================
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
      final listKeys = ['items', 'data', 'parts', 'results'];
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

  // ====================== Office APIs ======================

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

  static Future<Map<String, dynamic>> getCompany({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/company');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load company: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/company');
  }

  static Future<List<Map<String, dynamic>>> getBranches({
    required String token,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/branches').replace(
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
      throw Exception('Failed to load branches: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/branches');
  }

  static Future<List<Map<String, dynamic>>> getPosDevices({
    required String token,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/pos').replace(
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
      throw Exception('Failed to load POS devices: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/pos');
  }

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
      uri = Uri.parse('$baseUrl/user-branches');
    }

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load user branches: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/user-branches');
  }

  // ====================== Bills (ตะกร้า / ใบเสร็จ) ======================

  // GET /bills?limit=&offset=
  static Future<List<Map<String, dynamic>>> getBills({
    required String token,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/bills',
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
        'Failed to load bills: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/bills');
  }

  // /bills/switch — สร้างบิลใหม่ (targetBillId ว่าง) หรือสลับไปบิลอื่น
  static Future<Map<String, dynamic>> switchBill({
    required String token,
    String? targetBillId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/switch');

    final body = <String, dynamic>{
      'targetBillId': targetBillId ?? '',
    };

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to switch bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/switch');
  }

  // /bills/:id/add-item — เพิ่มสินค้าจาก partCode + addressCode
  static Future<Map<String, dynamic>> addItemToBill({
    required String token,
    required String billId,
    required String partCode,
    required String addressCode,
    int qty = 1,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/add-item');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'partCode': partCode,
        'addressCode': addressCode,
        'qty': qty,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to add item to bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/add-item');
  }

  // /bills/:id/add-item-by-barcode — เพิ่มสินค้าจากบาร์โค้ด
  static Future<Map<String, dynamic>> addItemToBillByBarcode({
    required String token,
    required String billId,
    required String barcode,
    int qty = 1,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/add-item-by-barcode');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'barcode': barcode, 'qty': qty}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to add item by barcode: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/add-item-by-barcode');
  }

  // /bills/:id/remove-item — ลบ/ลดจำนวนสินค้าในบิล
  static Future<Map<String, dynamic>> removeItemFromBill({
    required String token,
    required String billId,
    required String partCode,
    required String addressCode,
    int qty = 1,
    bool isRemoveAll = false,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/remove-item');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'partCode': partCode,
        'addressCode': addressCode,
        'qty': qty,
        'isRemoveAll': isRemoveAll,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to remove item from bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/remove-item');
  }

  // /bills/:id/add-discount — ใช้ promotionCode
  static Future<Map<String, dynamic>> addBillDiscount({
    required String token,
    required String billId,
    required String promotionCode,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/add-discount');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'promotionCode': promotionCode}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to add discount: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/add-discount');
  }

  // /bills/:id/remove-discount — ลบส่วนลด
  static Future<Map<String, dynamic>> removeBillDiscount({
    required String token,
    required String billId,
    required String promotionCode,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/remove-discount');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'promotionCode': promotionCode}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to remove discount: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/remove-discount');
  }

  // /bills/:id/payment — ชำระเงิน
  static Future<Map<String, dynamic>> payBill({
    required String token,
    required String billId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/payment');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to pay bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/payment');
  }

  // /bills/:id — ดึงบิลเต็ม ๆ (ใช้ตอน refresh)
  static Future<Map<String, dynamic>> getBill({
    required String token,
    required String billId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId');

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id');
  }

  // /bills/:id/cancel — ยกเลิกบิล (ต้องมี endpoint นี้ที่ backend)
  static Future<void> cancelBill({
    required String token,
    required String billId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/cancel');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to cancel bill: ${response.statusCode} ${response.body}',
      );
    }
  }
}
