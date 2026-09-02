import 'dart:convert';

import 'api_error.dart';

/// One Thai sentence for anything a POS action can fail with.
///
/// Calls made through the API layer arrive as [ApiException] and already know
/// their own wording. Everything else — an older call site, a thrown string,
/// a network failure — is squeezed for an embedded JSON body first, so a red
/// bar never shows a status code and a brace to a cashier.
String posErrorMessage(Object error) {
  if (error is ApiException) return error.toString();

  final raw = error.toString();
  final payload = _embeddedPayload(raw);
  if (payload != null) {
    final code = payload['error'];
    final message = payload['message'];
    return describeApiError(
      code: code is String && code.isNotEmpty ? code : null,
      serverMessage: message is String && message.trim().isNotEmpty
          ? message.trim()
          : null,
      statusCode: _embeddedStatus(raw),
      payload: payload,
    );
  }

  return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
}

/// The JSON object an older `Exception('… 400 {…}')` carries inside its text.
Map<String, dynamic>? _embeddedPayload(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) return null;
  final end = raw.lastIndexOf('}');
  if (end <= start) return null;
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

int? _embeddedStatus(String raw) {
  final match = RegExp(r'\b([45]\d{2})\b\s*\{').firstMatch(raw);
  return match == null ? null : int.tryParse(match.group(1)!);
}
