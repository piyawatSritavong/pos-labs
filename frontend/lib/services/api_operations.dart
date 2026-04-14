import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiOperationsService {
  static const bool _isProduction = bool.fromEnvironment('dart.vm.product');
  static const String baseUrl =
      _isProduction ? 'http://54.169.213.40:8080' : 'http://localhost:8080';

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic> _parseObject(
      dynamic decoded, String endpointName) {
    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] is Map<String, dynamic>) {
        return decoded['data'] as Map<String, dynamic>;
      }
      return decoded;
    }
    throw Exception('Unexpected $endpointName response format: $decoded');
  }

  static List<Map<String, dynamic>> _parseList(
      dynamic decoded, String endpointName) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] is List) {
        return (decoded['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      // try first List value
      for (final v in decoded.values) {
        if (v is List) {
          return v.whereType<Map<String, dynamic>>().toList();
        }
      }
    }
    throw Exception('Unexpected $endpointName response format: $decoded');
  }

  // ======================================================================
  // INVENTORY TRANSFER
  // ======================================================================

  // GET /transfers
  static Future<List<Map<String, dynamic>>> getTransfers({
    required String token,
    String? status,
    String? fromBranchId,
    String? toBranchId,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (fromBranchId != null && fromBranchId.isNotEmpty) {
      params['fromBranchId'] = fromBranchId;
    }
    if (toBranchId != null && toBranchId.isNotEmpty) {
      params['toBranchId'] = toBranchId;
    }

    final uri =
        Uri.parse('$baseUrl/transfers').replace(queryParameters: params);
    final response =
        await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /transfers failed: ${response.statusCode} ${response.body}');
    }
    return _parseList(jsonDecode(response.body), '/transfers');
  }

  // POST /transfers
  static Future<Map<String, dynamic>> createTransfer({
    required String token,
    required String fromBranchId,
    required String toBranchId,
    String notes = '',
    required List<Map<String, dynamic>> items,
  }) async {
    final uri = Uri.parse('$baseUrl/transfers');
    final response = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({
        'fromBranchId': fromBranchId,
        'toBranchId': toBranchId,
        'notes': notes,
        'items': items,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'POST /transfers failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/transfers');
  }

  // GET /transfers/:id
  static Future<Map<String, dynamic>> getTransfer({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/transfers/$id');
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /transfers/$id failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/transfers/:id');
  }

  // PUT /transfers/:id/approve
  static Future<Map<String, dynamic>> approveTransfer({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/transfers/$id/approve');
    final response =
        await http.put(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'PUT /transfers/$id/approve failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/transfers/:id/approve');
  }

  // PUT /transfers/:id/dispatch
  static Future<Map<String, dynamic>> dispatchTransfer({
    required String token,
    required String id,
    required List<Map<String, dynamic>> items,
  }) async {
    final uri = Uri.parse('$baseUrl/transfers/$id/dispatch');
    final response = await http.put(
      uri,
      headers: _headers(token),
      body: jsonEncode({'items': items}),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'PUT /transfers/$id/dispatch failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/transfers/:id/dispatch');
  }

  // PUT /transfers/:id/receive
  static Future<Map<String, dynamic>> receiveTransfer({
    required String token,
    required String id,
    required List<Map<String, dynamic>> items,
  }) async {
    final uri = Uri.parse('$baseUrl/transfers/$id/receive');
    final response = await http.put(
      uri,
      headers: _headers(token),
      body: jsonEncode({'items': items}),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'PUT /transfers/$id/receive failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/transfers/:id/receive');
  }

  // PUT /transfers/:id/cancel
  static Future<Map<String, dynamic>> cancelTransfer({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/transfers/$id/cancel');
    final response =
        await http.put(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'PUT /transfers/$id/cancel failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/transfers/:id/cancel');
  }

  // PUT /transfers/:id/acknowledge  (requested → pending)
  static Future<Map<String, dynamic>> acknowledgeTransfer({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/transfers/$id/acknowledge');
    final response = await http.put(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'PUT /transfers/$id/acknowledge failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(
        jsonDecode(response.body), '/transfers/:id/acknowledge');
  }

  // ======================================================================
  // STOCK COUNT
  // ======================================================================

  // GET /stock-counts
  static Future<List<Map<String, dynamic>>> getStockCounts({
    required String token,
    String? branchId,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (branchId != null && branchId.isNotEmpty) params['branchId'] = branchId;
    if (status != null && status.isNotEmpty) params['status'] = status;

    final uri =
        Uri.parse('$baseUrl/stock-counts').replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /stock-counts failed: ${response.statusCode} ${response.body}');
    }
    return _parseList(jsonDecode(response.body), '/stock-counts');
  }

  // POST /stock-counts
  static Future<Map<String, dynamic>> createStockCount({
    required String token,
    required String branchId,
    String storeId = '',
    String notes = '',
  }) async {
    final uri = Uri.parse('$baseUrl/stock-counts');
    final body = <String, dynamic>{
      'branchId': branchId,
      'notes': notes,
    };
    if (storeId.isNotEmpty) body['storeId'] = storeId;

    final response = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'POST /stock-counts failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/stock-counts');
  }

  // GET /stock-counts/:id
  static Future<Map<String, dynamic>> getStockCount({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/stock-counts/$id');
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /stock-counts/$id failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/stock-counts/:id');
  }

  // PUT /stock-counts/:id/items
  static Future<Map<String, dynamic>> updateStockCountItems({
    required String token,
    required String id,
    required List<Map<String, dynamic>> items,
  }) async {
    final uri = Uri.parse('$baseUrl/stock-counts/$id/items');
    final response = await http.put(
      uri,
      headers: _headers(token),
      body: jsonEncode({'items': items}),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'PUT /stock-counts/$id/items failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/stock-counts/:id/items');
  }

  // PUT /stock-counts/:id/submit
  static Future<Map<String, dynamic>> submitStockCount({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/stock-counts/$id/submit');
    final response = await http.put(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'PUT /stock-counts/$id/submit failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/stock-counts/:id/submit');
  }

  // ======================================================================
  // DAILY CLOSE
  // ======================================================================

  // GET /daily-closes
  static Future<List<Map<String, dynamic>>> getDailyCloses({
    required String token,
    String? branchId,
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (branchId != null && branchId.isNotEmpty) params['branchId'] = branchId;
    if (dateFrom != null && dateFrom.isNotEmpty) params['dateFrom'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) params['dateTo'] = dateTo;

    final uri =
        Uri.parse('$baseUrl/daily-closes').replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /daily-closes failed: ${response.statusCode} ${response.body}');
    }
    return _parseList(jsonDecode(response.body), '/daily-closes');
  }

  // GET /daily-closes/summary
  static Future<Map<String, dynamic>> getDailyCloseSummary({
    required String token,
    required String branchId,
    required String posId,
  }) async {
    final params = <String, String>{
      'branchId': branchId,
      'posId': posId,
    };
    final uri = Uri.parse('$baseUrl/daily-closes/summary')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /daily-closes/summary failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/daily-closes/summary');
  }

  // POST /daily-closes
  static Future<Map<String, dynamic>> createDailyClose({
    required String token,
    required String branchId,
    required String posId,
    String notes = '',
  }) async {
    final uri = Uri.parse('$baseUrl/daily-closes');
    final response = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({
        'branchId': branchId,
        'posId': posId,
        'notes': notes,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'POST /daily-closes failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/daily-closes');
  }

  // GET /daily-closes/:id
  static Future<Map<String, dynamic>> getDailyClose({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/daily-closes/$id');
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /daily-closes/$id failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/daily-closes/:id');
  }

  // ======================================================================
  // CASH RECONCILIATION
  // ======================================================================

  // GET /cash-reconciliations
  static Future<List<Map<String, dynamic>>> getCashReconciliations({
    required String token,
    String? branchId,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (branchId != null && branchId.isNotEmpty) params['branchId'] = branchId;

    final uri = Uri.parse('$baseUrl/cash-reconciliations')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /cash-reconciliations failed: ${response.statusCode} ${response.body}');
    }
    return _parseList(jsonDecode(response.body), '/cash-reconciliations');
  }

  // POST /cash-reconciliations
  static Future<Map<String, dynamic>> createCashReconciliation({
    required String token,
    required String dailyCloseId,
    required double actualAmount,
    String notes = '',
  }) async {
    final uri = Uri.parse('$baseUrl/cash-reconciliations');
    final response = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({
        'dailyCloseId': dailyCloseId,
        'actualAmount': actualAmount,
        'notes': notes,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'POST /cash-reconciliations failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/cash-reconciliations');
  }

  // GET /cash-reconciliations/:id
  static Future<Map<String, dynamic>> getCashReconciliation({
    required String token,
    required String id,
  }) async {
    final uri = Uri.parse('$baseUrl/cash-reconciliations/$id');
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /cash-reconciliations/$id failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(
        jsonDecode(response.body), '/cash-reconciliations/:id');
  }

  // ======================================================================
  // STOCK VARIANCE REPORT
  // ======================================================================

  // GET /reports/stock-variance?countId=
  static Future<Map<String, dynamic>> getStockVariance({
    required String token,
    required String countId,
  }) async {
    final uri = Uri.parse('$baseUrl/reports/stock-variance')
        .replace(queryParameters: {'countId': countId});
    final response = await http.get(uri, headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception(
          'GET /reports/stock-variance failed: ${response.statusCode} ${response.body}');
    }
    return _parseObject(jsonDecode(response.body), '/reports/stock-variance');
  }
}
