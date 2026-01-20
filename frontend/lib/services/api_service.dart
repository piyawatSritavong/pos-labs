import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  // ตรวจสอบว่าแอปกำลังรันอยู่ในโหมด Release (Production) หรือไม่
  static const bool _isProduction = bool.fromEnvironment('dart.vm.product');
  static const String baseUrl = _isProduction
      ? 'http://54.169.213.40:8080'
      : 'http://localhost:8080';

  static const String _branchId = '00000';
  static const String _posId = 'POS001';
  // ใช้ String.fromEnvironment เพื่อดึงค่าตอน Build
  static const String _posSecret = String.fromEnvironment(
    'POS_SECRET',
    defaultValue: 'default_if_needed',
  );

  // ======================================================================
  // 0) Helpers
  // ======================================================================

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

  // ======================================================================
  // 1) /auth
  // ======================================================================

  // 1.1) POST /auth/login
  static Future<String> login(String username, String password) async {
    final uri = Uri.parse('$baseUrl/auth/login');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'branchId': _branchId,
        'posId': _posId,
        'posSecret': _posSecret,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Login failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body);

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

  // 1.2) GET /auth/me
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

  // ======================================================================
  // 2) /health
  // ======================================================================

  // 2.1) GET /health
  static Future<Map<String, dynamic>> getHealth() async {
    final uri = Uri.parse('$baseUrl/health');

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get health: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    // กรณี backend ส่งอย่างอื่นกลับมา (เช่น string) ให้ห่อเป็น map ไว้ใช้งานง่าย ๆ
    return {'raw': decoded};
  }

  // ======================================================================
  // 3) /bills
  // ======================================================================

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

  // PUT /bills/switch — สร้างบิลใหม่ (targetBillId ว่าง) หรือสลับไปบิลอื่น
  static Future<Map<String, dynamic>> switchBill({
    required String token,
    String? targetBillId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/switch');

    final body = <String, dynamic>{'targetBillId': targetBillId ?? ''};

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

  // PUT /bills/:id/add-item — เพิ่มสินค้าจาก partCode + addressCode
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

  // PUT /bills/:id/add-item-by-barcode — เพิ่มสินค้าจากบาร์โค้ด
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
    return _extractObjectFromResponse(
      decoded,
      '/bills/:id/add-item-by-barcode',
    );
  }

  // PUT /bills/:id/remove-item — ลบ/ลดจำนวนสินค้าในบิล
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

  // PUT /bills/:id/add-discount — ใช้ promotionCode
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

  // PUT /bills/:id/remove-discount — ลบส่วนลด
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

  // PUT /bills/:id/payment — ชำระเงิน
  static Future<Map<String, dynamic>> payBill({
    required String token,
    required String billId,
    String paymentMethod = 'cash',
    String? paymentRef,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/payment');

    final body = <String, dynamic>{'paymentMethod': paymentMethod};
    if (paymentRef != null && paymentRef.isNotEmpty) {
      body['paymentRef'] = paymentRef;
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
      throw Exception(
        'Failed to pay bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/payment');
  }

  // GET /bills/:id — ดึงบิลเต็ม ๆ (ใช้ตอน refresh)
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

  // /bills/:id/cancel — ยกเลิกบิล
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

  // POST /bills - สร้างบิลใหม่ (ว่าง) ใช้ branchId/posId จาก session
  static Future<Map<String, dynamic>> createBill({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/bills');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      // ตาม Postman ใช้ body ว่าง ๆ "{}"
      body: jsonEncode({}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills');
  }

  // PUT /bills/:id/hold - เปลี่ยนสถานะบิลเป็น hold
  static Future<Map<String, dynamic>> holdBill({
    required String token,
    required String billId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/hold');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to hold bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/hold');
  }

  // DELETE /bills/:id - ลบบิลพร้อมรายละเอียดทั้งหมด
  static Future<void> deleteBill({
    required String token,
    required String billId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId');

    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete bill: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ======================================================================
  // 4) /branches
  // ======================================================================

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
    String companyId = '0000000000000',
    String? branchNameTh,
    String? address,
    String? addressTh,
    String? phone,
    String? email,
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
        'companyId': companyId,
        'branchName': branchName,
        'branchNameTh': branchNameTh ?? '',
        'branchAddress': address ?? '',
        'branchAddressTh': addressTh ?? '',
        'phone': phone ?? '',
        'email': email ?? '',
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
    String companyId = '0000000000000',
    String? branchNameTh,
    String? address,
    String? addressTh,
    String? phone,
    String? email,
    bool? isActive,
  }) async {
    final uri = Uri.parse('$baseUrl/branches/$branchId');

    final body = <String, dynamic>{
      'companyId': companyId,
      'branchName': branchName,
      'branchNameTh': branchNameTh ?? '',
      'branchAddress': address ?? '',
      'branchAddressTh': addressTh ?? '',
      'phone': phone ?? '',
      'email': email ?? '',
    };

    if (isActive != null) {
      body['isActive'] = isActive;
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

  // ======================================================================
  // 5) /company
  // ======================================================================

  // GET /company - ดึงข้อมูล company
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
      throw Exception(
        'Failed to load company: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/company');
  }

  // PUT /company - อัพเดทข้อมูล company
  static Future<Map<String, dynamic>> updateCompany({
    required String token,
    required String companyName,
    required String companyNameTh,
    required String companyAddress,
    required String companyAddressTh,
    required String phone,
    required String email,
    required String website,
    String? logoUrl,
    required double taxRate,
    required String taxType,
  }) async {
    final uri = Uri.parse('$baseUrl/company');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'companyName': companyName,
        'companyNameTh': companyNameTh,
        'companyAddress': companyAddress,
        'companyAddressTh': companyAddressTh,
        'phone': phone,
        'email': email,
        'website': website,
        'logoUrl': logoUrl ?? '',
        'taxRate': taxRate,
        'taxType': taxType,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update company: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/company');
  }

  // ======================================================================
  // 6) /parts
  // ======================================================================

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

  // ======================================================================
  // 7) /pos
  // ======================================================================

  // GET /pos - ดึงรายการอุปกรณ์ POS
  static Future<List<Map<String, dynamic>>> getPosDevices({
    required String token,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/pos',
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
        'Failed to load POS devices: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/pos');
  }

  // GET /pos/:id - ดึงรายละเอียด POS ตาม ID
  static Future<Map<String, dynamic>> getPosById({
    required String token,
    required String posId,
  }) async {
    final uri = Uri.parse('$baseUrl/pos/$posId');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load POS: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/pos/:id');
  }

  // POST /pos - สร้าง POS ใหม่
  static Future<Map<String, dynamic>> createPos({
    required String token,
    required String posId,
    required String branchId,
    required String posName,
  }) async {
    final uri = Uri.parse('$baseUrl/pos');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'posId': posId,
        'branchId': branchId,
        'posName': posName,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create POS: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/pos');
  }

  // PUT /pos/:id/toggle-activate - สลับสถานะเปิด/ปิดการใช้งาน POS
  static Future<Map<String, dynamic>> togglePosActivate({
    required String token,
    required String posId,
  }) async {
    final uri = Uri.parse('$baseUrl/pos/$posId/toggle-activate');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to toggle POS active status: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/pos/:id/toggle-activate');
  }

  // GET /pos/:id/secret - ดึง POS secret สำหรับ login
  static Future<Map<String, dynamic>> getPosSecret({
    required String token,
    required String posId,
  }) async {
    final uri = Uri.parse('$baseUrl/pos/$posId/secret');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get POS secret: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/pos/:id/secret');
  }

  // PUT /pos/:id/secret - รีเฟรช/เปลี่ยน POS secret
  static Future<Map<String, dynamic>> refreshPosSecret({
    required String token,
    required String posId,
  }) async {
    final uri = Uri.parse('$baseUrl/pos/$posId/secret');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to refresh POS secret: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/pos/:id/secret');
  }

  // DELETE /pos/:id - ลบ POS
  static Future<void> deletePos({
    required String token,
    required String posId,
  }) async {
    final uri = Uri.parse('$baseUrl/pos/$posId');
    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete POS: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ======================================================================
  // 8) /promotions
  // ======================================================================

  // GET /promotions - ดึงรายการโปรโมชั่น
  static Future<List<Map<String, dynamic>>> getPromotions({
    required String token,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/promotions',
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
        'Failed to load promotions: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/promotions');
  }

  // GET /promotions/:code - ดึงรายละเอียดโปรโมชั่นตาม code
  static Future<Map<String, dynamic>> getPromotionByCode({
    required String token,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/promotions/$code');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load promotion: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/promotions/:code');
  }

  // POST /promotions - สร้างโปรโมชั่นใหม่
  static Future<Map<String, dynamic>> createPromotion({
    required String token,
    required String code,
    required String details,
    required String unit,
    required num amount,
  }) async {
    final uri = Uri.parse('$baseUrl/promotions');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'code': code,
        'details': details,
        'unit': unit,
        'amount': amount,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create promotion: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/promotions');
  }

  // PUT /promotions/:code - อัปเดตโปรโมชั่น
  static Future<Map<String, dynamic>> updatePromotion({
    required String token,
    required String code,
    required String details,
    required String unit,
    required num amount,
  }) async {
    final uri = Uri.parse('$baseUrl/promotions/$code');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'details': details, 'unit': unit, 'amount': amount}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update promotion: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/promotions/:code');
  }

  // DELETE /promotions/:code - ลบโปรโมชั่น
  static Future<void> deletePromotion({
    required String token,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/promotions/$code');
    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete promotion: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ======================================================================
  // 9) /promotions
  // ======================================================================

  // GET /addresses - ดึงรายการที่อยู่สินค้า (store address)
  static Future<List<Map<String, dynamic>>> getAddresses({
    required String token,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/addresses',
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
        'Failed to load addresses: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/addresses');
  }

  // GET /addresses/:code - ดึงรายละเอียด address ตาม code
  static Future<Map<String, dynamic>> getAddressByCode({
    required String token,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/addresses/$code');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load address: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/addresses/:code');
  }

  // POST /addresses - สร้าง address ใหม่
  static Future<Map<String, dynamic>> createAddress({
    required String token,
    required String code,
    required String partCode,
    required String storeId,
    String? shelf,
    int? qty,
    int? min,
    int? max,
    int? rop,
    String? remarks,
  }) async {
    final uri = Uri.parse('$baseUrl/addresses');
    final body = <String, dynamic>{
      'code': code,
      'partCode': partCode,
      'storeId': storeId,
      'shelf': shelf,
      'qty': qty,
      'min': min,
      'max': max,
      'rop': rop,
      'remarks': remarks,
    }..removeWhere((key, value) => value == null);

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create address: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/addresses');
  }

  // PUT /addresses/:code - อัปเดต address
  static Future<Map<String, dynamic>> updateAddress({
    required String token,
    required String code,
    required String partCode,
    required String storeId,
    String? shelf,
    int? qty,
    int? min,
    int? max,
    int? rop,
    String? remarks,
  }) async {
    final uri = Uri.parse('$baseUrl/addresses/$code');
    final body = <String, dynamic>{
      'partCode': partCode,
      'storeId': storeId,
      'shelf': shelf,
      'qty': qty,
      'min': min,
      'max': max,
      'rop': rop,
      'remarks': remarks,
    }..removeWhere((key, value) => value == null);

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
        'Failed to update address: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/addresses/:code');
  }

  // DELETE /addresses/:code - ลบ address
  static Future<void> deleteAddress({
    required String token,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/addresses/$code');
    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete address: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ======================================================================
  // 10) /assets
  // ======================================================================

  // GET /assets/qr-image - ดึงรูป QR (binary)
  static Future<Uint8List> getQrImage({required String token}) async {
    final uri = Uri.parse('$baseUrl/assets/qr-image');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load QR image: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  // PUT /assets/qr-image - อัปโหลด/แทนที่รูป QR (binary)
  static Future<void> uploadQrImage({
    required String token,
    required Uint8List bytes,
    String contentType = 'image/png',
  }) async {
    final uri = Uri.parse('$baseUrl/assets/qr-image');
    final response = await http.put(
      uri,
      headers: {'Authorization': 'Bearer $token', 'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to upload QR image: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ======================================================================
  // 11) /user-branches
  // ======================================================================

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

  // ======================================================================
  // 12) /users
  // ======================================================================

  // GET /users
  static Future<List<Map<String, dynamic>>> getUsers({
    required String token,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/users',
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
        'Failed to load users: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/users');
  }

  // GET /users/:id
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
      throw Exception(
        'Failed to load user: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/users/:id');
  }

  // POST /users
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
      throw Exception(
        'Failed to create user: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/users');
  }

  // PUT /users/:id
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
      throw Exception(
        'Failed to update user: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/users/:id');
  }

  // DELETE /users/:id
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
      throw Exception(
        'Failed to delete user: ${response.statusCode} ${response.body}',
      );
    }
  }
}
