import 'dart:convert';
import 'package:frontend/config/api_config.dart';
import 'package:http/http.dart' as http;
import '../utils/api_error.dart';

class ApiBillsService {
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
      final listKeys = ['items', 'data', 'users', 'parts', 'results', 'bills'];
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

  static bool _looksLikeBillObject(Map<String, dynamic> payload) {
    return payload.containsKey('purchaseAmount') ||
        payload.containsKey('totalAmount') ||
        payload.containsKey('status') ||
        payload.containsKey('details') ||
        payload.containsKey('discounts');
  }

  // GET /bills?limit=&offset=
  static Future<List<Map<String, dynamic>>> getBills({
    required String token,
    int limit = 20,
    int offset = 0,
    List<String>? statuses,
    bool includeDetails = false,
    String scope = 'pos',
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'scope': scope,
    };
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
      throw ApiException(
        action: 'Failed to load bills',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to switch bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to add item to bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to add item by barcode',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to remove item from bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to update item price',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to add discount',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to remove discount',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to pay bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to fetch bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to cancel bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to create bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to hold bill',
        statusCode: response.statusCode,
        body: response.body,
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
      throw ApiException(
        action: 'Failed to delete bill',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }
}
