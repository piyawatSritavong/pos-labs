import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as client;

class ApiAuthFailure {
  const ApiAuthFailure(this.code);
  final String code;
}

class ApiHttpEvents {
  ApiHttpEvents._();

  static final StreamController<ApiAuthFailure> _authFailures =
      StreamController<ApiAuthFailure>.broadcast();

  static Stream<ApiAuthFailure> get authFailures => _authFailures.stream;
  static DateTime? _lastAuthFailure;

  static bool get hasRecentAuthFailure {
    final value = _lastAuthFailure;
    return value != null &&
        DateTime.now().difference(value) < const Duration(seconds: 3);
  }

  static void _notifyAuthFailure(String code) {
    _lastAuthFailure = DateTime.now();
    _authFailures.add(ApiAuthFailure(code));
  }
}

Future<client.Response> _inspect(
  Uri url,
  Future<client.Response> request,
) async {
  final response = await request;
  if (response.statusCode != 401 || url.path.endsWith('/auth/login')) {
    return response;
  }

  var code = 'unauthorized';
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['error'] is String) {
      code = decoded['error'] as String;
    }
  } catch (_) {
    // A malformed 401 is still an authentication failure.
  }
  // Credential checks are not bearer-session failures. In particular,
  // /auth/verify-password may legitimately return this while the current
  // application session remains valid.
  if (code != 'invalid_credentials') {
    ApiHttpEvents._notifyAuthFailure(code);
  }
  return response;
}

Future<client.Response> get(Uri url, {Map<String, String>? headers}) =>
    _inspect(url, client.get(url, headers: headers));

Future<client.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _inspect(
  url,
  client.post(url, headers: headers, body: body, encoding: encoding),
);

Future<client.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _inspect(
  url,
  client.put(url, headers: headers, body: body, encoding: encoding),
);

Future<client.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _inspect(
  url,
  client.patch(url, headers: headers, body: body, encoding: encoding),
);

Future<client.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _inspect(
  url,
  client.delete(url, headers: headers, body: body, encoding: encoding),
);

Future<client.Response> head(Uri url, {Map<String, String>? headers}) =>
    _inspect(url, client.head(url, headers: headers));
