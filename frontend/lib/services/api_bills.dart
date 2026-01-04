import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiBillsService {
  static const String baseUrl = 'http://localhost:8080';

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
    return _extractObjectFromResponse(
      decoded,
      '/bills/:id/add-item-by-barcode',
    );
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
