import 'dart:convert';
import 'dart:typed_data';
import 'package:frontend/config/api_config.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static String get baseUrl => ApiConfig.apiBaseUrl;

  static const String _branchId = '00000';
  static const String _posId = 'POS001';
  // ใช้ String.fromEnvironment เพื่อดึงค่าตอน Build
  static const String _posSecret = String.fromEnvironment(
    'POS_SECRET',
    defaultValue: 'default_if_needed',
  );
  static const String defaultBranchId = _branchId;
  static const String defaultPosId = _posId;
  static const String posSecret = _posSecret;

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
      final listKeys = [
        'items',
        'data',
        'users',
        'parts',
        'results',
        'members',
        'bills',
        'branches',
        'promotions',
        'addresses',
        'userBranches',
        'devices',
        'pos',
        'returns',
      ];
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

  // 1.15) POST /auth/verify-password (checks password without touching sessions)
  static Future<bool> verifyPassword({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/verify-password');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return response.statusCode == 200;
  }

  // 1.2) POST /auth/logout
  static Future<void> logout(String token) async {
    final uri = Uri.parse('$baseUrl/auth/logout');

    final response = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Logout failed: ${response.statusCode} ${response.body}');
    }
  }

  // 1.3) GET /auth/me
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
  // Feature: POS Checkout / Hold Bill / Return Flow (อ้างอิงบิลเดิมผ่าน transaction)
  // ======================================================================

  // GET /bills?limit=&offset=&date=&date_from=&date_to=
  static Future<List<Map<String, dynamic>>> getBills({
    required String token,
    int limit = 20,
    int offset = 0,
    String? date,
    String? dateFrom,
    String? dateTo,
    String? memberId,
    List<String>? statuses,
    bool includeDetails = false,
    String scope = 'branch',
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'scope': scope,
    };

    // According to backend docs, `date` is mutually exclusive with `date_from`/`date_to`.
    if (date != null && date.isNotEmpty) {
      queryParams['date'] = date;
    } else {
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['date_from'] = dateFrom;
      }
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['date_to'] = dateTo;
      }
    }
    if (memberId != null && memberId.isNotEmpty) {
      queryParams['memberId'] = memberId;
    }
    if (statuses != null && statuses.isNotEmpty) {
      queryParams['statuses'] = statuses.join(',');
    }
    if (includeDetails) {
      queryParams['includeDetails'] = 'true';
    }

    final uri = Uri.parse(
      '$baseUrl/bills',
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

  // PUT /bills/:id/update-item-price — แก้ยอดราคาของรายการสินค้าในบิล
  static Future<Map<String, dynamic>> updateItemPriceInBill({
    required String token,
    required String billId,
    required String partCode,
    required String addressCode,
    required double lineTotal,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/update-item-price');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'partCode': partCode,
        'addressCode': addressCode,
        'lineTotal': lineTotal,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update item price: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final payload = _extractObjectFromResponse(
      decoded,
      '/bills/:id/update-item-price',
    );
    if (_looksLikeBillObject(payload)) {
      return payload;
    }
    return getBill(token: token, billId: billId);
  }

  static bool _looksLikeBillObject(Map<String, dynamic> payload) {
    return payload.containsKey('purchaseAmount') ||
        payload.containsKey('totalAmount') ||
        payload.containsKey('status') ||
        payload.containsKey('details') ||
        payload.containsKey('discounts');
  }

  // PUT /bills/:id/add-discount — ใช้ promotionCode หรือ manual unit+amount
  static Future<Map<String, dynamic>> addBillDiscount({
    required String token,
    required String billId,
    String? promotionCode,
    String? unit,
    double? amount,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/add-discount');

    final body = <String, dynamic>{};
    if (promotionCode != null && promotionCode.isNotEmpty) {
      body['promotionCode'] = promotionCode;
    }
    if (unit != null && unit.isNotEmpty) {
      body['unit'] = unit;
    }
    if (amount != null) {
      body['amount'] = amount;
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
        'Failed to add discount: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final payload = _extractObjectFromResponse(
      decoded,
      '/bills/:id/add-discount',
    );
    if (_looksLikeBillObject(payload)) {
      return payload;
    }
    return getBill(token: token, billId: billId);
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
    final payload = _extractObjectFromResponse(
      decoded,
      '/bills/:id/remove-discount',
    );
    if (_looksLikeBillObject(payload)) {
      return payload;
    }
    return getBill(token: token, billId: billId);
  }

  // Feature: POS - ผูกสมาชิกเข้าบิล (ค้นหาจากเบอร์โทร)
  // PUT /bills/:id/add-member-by-phone
  static Future<Map<String, dynamic>> addMemberToBillByPhone({
    required String token,
    required String billId,
    required String phone,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/add-member-by-phone');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'phone': phone}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to add member to bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(
      decoded,
      '/bills/:id/add-member-by-phone',
    );
  }

  // Feature: POS - ถอดสมาชิกออกจากบิล
  // PUT /bills/:id/remove-member
  static Future<Map<String, dynamic>> removeMemberFromBill({
    required String token,
    required String billId,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/remove-member');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to remove member from bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/bills/:id/remove-member');
  }

  // PUT /bills/:id/payment — ชำระเงิน
  static Future<Map<String, dynamic>> payBill({
    required String token,
    required String billId,
    String paymentMethod = 'cash',
    String? paymentRef,
    Object? paymentMeta,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/payment');

    final body = <String, dynamic>{'paymentMethod': paymentMethod};
    if (paymentRef != null && paymentRef.isNotEmpty) {
      body['paymentRef'] = paymentRef;
    }
    if (paymentMeta != null) {
      body['paymentMeta'] = paymentMeta;
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

  // POST /bills/:id/print — สั่งพิมพ์ใบเสร็จไป backend (ESC-POS → LPT1 / printer share)
  //
  // เรียกอัตโนมัติเมื่อ _ReceiptDialog เปิด หลังบันทึกชำระเงินสำเร็จ
  // ถ้า backend ตอบ error จะ throw เพื่อให้ dialog ค้างไว้และกด retry ได้
  static Future<Map<String, dynamic>> printReceipt({
    required String token,
    required String billId,
    String? idempotencyKey,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/$billId/print');
    final body = <String, dynamic>{};
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      body['idempotencyKey'] = idempotencyKey;
    }
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'พิมพ์ใบเสร็จไม่สำเร็จ: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'ok': true};
  }

  static Future<Map<String, dynamic>> printTestReceipt({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/bills/print-test');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'พิมพ์ใบเสร็จทดสอบไม่สำเร็จ: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'ok': true};
  }

  // POST /returns/:id/print — พิมพ์ใบคืนสินค้า/คืนเงินหลังสร้าง return note สำเร็จ
  static Future<Map<String, dynamic>> printReturnReceipt({
    required String token,
    required String returnNoteId,
    String? idempotencyKey,
  }) async {
    final uri = Uri.parse('$baseUrl/returns/$returnNoteId/print');
    final body = <String, dynamic>{};
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      body['idempotencyKey'] = idempotencyKey;
    }
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'พิมพ์ใบคืนสินค้าไม่สำเร็จ: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'ok': true};
  }

  static Future<Map<String, dynamic>> sendCustomerDisplayTestState({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/pos-mirror/test-state');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'ส่งข้อมูลทดสอบจอลูกค้าไม่สำเร็จ: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'ok': true};
  }

  // GET /returns/reference/:billId — ดึงบิลอ้างอิงสำหรับคืนสินค้า พร้อม qty ที่ยังคืนได้
  static Future<Map<String, dynamic>> getReturnReferenceBill({
    required String token,
    required String billId,
  }) async {
    final uri = Uri.parse('$baseUrl/returns/reference/$billId');

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch return reference bill: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/returns/reference/:billId');
  }

  // POST /returns — สร้าง credit note การคืนสินค้า
  static Future<Map<String, dynamic>> createReturnNote({
    required String token,
    required String referenceBillId,
    required String settlementMode,
    required List<Map<String, dynamic>> lines,
    String? purchaseBillId,
    String? paymentMethod,
    String? paymentRef,
    Object? paymentMeta,
  }) async {
    final uri = Uri.parse('$baseUrl/returns');

    final body = <String, dynamic>{
      'referenceBillId': referenceBillId,
      'settlementMode': settlementMode,
      'lines': lines,
    };
    if (purchaseBillId != null && purchaseBillId.isNotEmpty) {
      body['purchaseBillId'] = purchaseBillId;
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      body['paymentMethod'] = paymentMethod;
    }
    if (paymentRef != null && paymentRef.isNotEmpty) {
      body['paymentRef'] = paymentRef;
    }
    if (paymentMeta != null) {
      body['paymentMeta'] = paymentMeta;
    }

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
        'Failed to create return note: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/returns');
  }

  // GET /returns — รายการ credit note / คืนสินค้า
  static Future<List<Map<String, dynamic>>> getReturnNotes({
    required String token,
    int limit = 100,
    int offset = 0,
    String scope = 'branch',
    bool includeDetails = false,
    String? date,
    String? dateFrom,
    String? dateTo,
    String? referenceBillId,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'scope': scope,
    };

    if (date != null && date.isNotEmpty) {
      queryParams['date'] = date;
    } else {
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['date_from'] = dateFrom;
      }
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['date_to'] = dateTo;
      }
    }
    if (referenceBillId != null && referenceBillId.isNotEmpty) {
      queryParams['referenceBillId'] = referenceBillId;
    }
    if (includeDetails) {
      queryParams['includeDetails'] = 'true';
    }

    final uri = Uri.parse(
      '$baseUrl/returns',
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
        'Failed to load return notes: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/returns');
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

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode == 409 && decoded is Map<String, dynamic>) {
      final existingBillId = decoded['existingBillId']?.toString() ?? '';
      if (existingBillId.isNotEmpty) {
        return {'id': existingBillId, 'existing': true};
      }
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create bill: ${response.statusCode} ${response.body}',
      );
    }

    if (decoded == null) {
      throw Exception('Unexpected /bills response format: ${response.body}');
    }
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
  // Feature: Branch Management (Backoffice)
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
  // Feature: Company Settings (Backoffice)
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
  // Feature: Product Search + Product Master (POS + Backoffice)
  // ======================================================================

  // GET /parts?limit=&offset=
  static Future<List<Map<String, dynamic>>> getParts({
    required String token,
    int limit = 20,
    int offset = 0,
    String? branchId,
  }) async {
    final params = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (branchId != null && branchId.isNotEmpty) params['branchId'] = branchId;
    final uri = Uri.parse('$baseUrl/parts').replace(queryParameters: params);

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
  // 7) /members
  // Feature: Member Management (Backoffice สมาชิก + POS ค้นหาสมาชิก)
  // ======================================================================

  // GET /members?limit=&offset=&q=
  static Future<List<Map<String, dynamic>>> getMembers({
    required String token,
    int limit = 20,
    int offset = 0,
    String? query,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (query != null && query.isNotEmpty) {
      queryParams['q'] = query;
    }

    final uri = Uri.parse(
      '$baseUrl/members',
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
        'Failed to load members: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/members');
  }

  // GET /members/search?q=&limit=&offset=
  static Future<List<Map<String, dynamic>>> searchMembers({
    required String token,
    required String query,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/members/search').replace(
      queryParameters: {'q': query, 'limit': '$limit', 'offset': '$offset'},
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to search members: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/members/search');
  }

  // GET /members/:id
  static Future<Map<String, dynamic>> getMemberById({
    required String token,
    required String memberId,
  }) async {
    final uri = Uri.parse('$baseUrl/members/$memberId');

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load member: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/members/:id');
  }

  // POST /members
  static Future<Map<String, dynamic>> createMember({
    required String token,
    required String name,
    required String phone,
    String? email,
    int points = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/members');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'email': email ?? '',
        'points': points,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create member: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/members');
  }

  // PUT /members/:id
  static Future<Map<String, dynamic>> updateMember({
    required String token,
    required String memberId,
    required String name,
    required String phone,
    String? email,
    int points = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/members/$memberId');

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'email': email ?? '',
        'points': points,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update member: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/members/:id');
  }

  // DELETE /members/:id
  static Future<void> deleteMember({
    required String token,
    required String memberId,
  }) async {
    final uri = Uri.parse('$baseUrl/members/$memberId');

    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete member: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ======================================================================
  // 8) /pos
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
  // 9) /promotions
  // Feature: Promotion Management (Backoffice)
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
  // 10) /addresses
  // Feature: Inventory Address Management (Backoffice + POS stock mapping)
  // ======================================================================

  // GET /addresses?q=&storeId=&limit=&offset= - ดึงรายการที่อยู่สินค้า (store address)
  // q/storeId ทำ server-side filter (แทนการโหลดทั้ง catalog แล้ว filter ใน Dart)
  static Future<List<Map<String, dynamic>>> getAddresses({
    required String token,
    int limit = 20,
    int offset = 0,
    String query = '',
    String? storeId,
  }) async {
    final params = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (query.isNotEmpty) params['q'] = query;
    if (storeId != null && storeId.isNotEmpty) params['storeId'] = storeId;
    final uri = Uri.parse(
      '$baseUrl/addresses',
    ).replace(queryParameters: params);
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
  // 11) /assets
  // Feature: Payment Settings (QR image upload/display)
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
  // 12) /reports
  // Feature: Reports/Export (Backoffice ดาวน์โหลด CSV)
  // ======================================================================

  // GET /reports/bills?date=YYYY-MM-DD&items=0|1  => CSV bytes
  static Future<Uint8List> exportBillsReportCsv({
    required String token,
    required String date,
    bool includeItems = false,
  }) async {
    final uri = Uri.parse('$baseUrl/reports/bills').replace(
      queryParameters: {'date': date, 'items': includeItems ? '1' : '0'},
    );

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to export bills report: ${response.statusCode} ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  // GET /reports/parts => CSV bytes
  static Future<Uint8List> exportPartsReportCsv({required String token}) async {
    final uri = Uri.parse('$baseUrl/reports/parts');

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to export parts report: ${response.statusCode} ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  // GET /reports/inventory => CSV bytes
  static Future<Uint8List> exportInventoryReportCsv({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/reports/inventory');

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to export inventory report: ${response.statusCode} ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  // ======================================================================
  // 13) /user-branches
  // Feature: Access Control (map user ↔ branch)
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

    // /user-branches/:user_id/:branch_id returns a single object
    if (userId != null && branchId != null) {
      final obj = _extractObjectFromResponse(
        decoded,
        '/user-branches/:user_id/:branch_id',
      );
      return [obj];
    }

    return _extractListFromResponse(decoded, '/user-branches');
  }

  // GET /user-branches/:user_id/:branch_id
  static Future<Map<String, dynamic>> getUserBranch({
    required String token,
    required String userId,
    required String branchId,
  }) async {
    final uri = Uri.parse('$baseUrl/user-branches/$userId/$branchId');

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load user branch: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(
      decoded,
      '/user-branches/:user_id/:branch_id',
    );
  }

  // POST /user-branches
  static Future<Map<String, dynamic>> createUserBranch({
    required String token,
    required String userId,
    required String branchId,
  }) async {
    final uri = Uri.parse('$baseUrl/user-branches');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'userId': userId, 'branchId': branchId}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create user branch: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/user-branches');
  }

  // DELETE /user-branches/:user_id/:branch_id
  static Future<void> deleteUserBranch({
    required String token,
    required String userId,
    required String branchId,
  }) async {
    final uri = Uri.parse('$baseUrl/user-branches/$userId/$branchId');

    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete user branch: ${response.statusCode} ${response.body}',
      );
    }
  }

  // ======================================================================
  // 14) /users
  // Feature: User Management (Backoffice)
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
  // GET /roles — list selectable roles (base + custom).
  static Future<List<Map<String, dynamic>>> getRoles({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/roles');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load roles: ${response.statusCode} ${response.body}',
      );
    }
    return _extractListFromResponse(jsonDecode(response.body), '/roles');
  }

  // POST /roles — create a custom role with the chosen permissions.
  // Returns {id, name}.
  static Future<Map<String, dynamic>> createRole({
    required String token,
    required String name,
    required List<String> permissions,
    String detail = '',
  }) async {
    final uri = Uri.parse('$baseUrl/roles');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name,
        'detail': detail,
        'permissions': permissions,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to create role: ${response.statusCode} ${response.body}',
      );
    }
    return _extractObjectFromResponse(jsonDecode(response.body), '/roles');
  }

  static Future<Map<String, dynamic>> createUser({
    required String token,
    required String username,
    required String roleId,
    required String name,
    required String password,
    bool isActive = true,
    bool isSuperuser = false,
    List<String>? customPermissions,
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
        if (customPermissions != null) 'customPermissions': customPermissions,
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
    List<String>? customPermissions,
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
    if (customPermissions != null) {
      body['customPermissions'] = customPermissions;
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
