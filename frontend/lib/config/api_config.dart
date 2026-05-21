class ApiConfig {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );
  static const String _wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl => _trimTrailingSlash(_apiBaseUrl);

  static String get wsBaseUrl {
    final override = _trimTrailingSlash(_wsBaseUrl);
    if (override.isNotEmpty) {
      return override;
    }
    final apiBase = apiBaseUrl;
    if (apiBase.startsWith('https://')) {
      return apiBase.replaceFirst('https://', 'wss://');
    }
    if (apiBase.startsWith('http://')) {
      return apiBase.replaceFirst('http://', 'ws://');
    }
    return apiBase;
  }

  static String wsUrl(String path, [Map<String, String>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$wsBaseUrl$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri.toString();
    }
    return uri.replace(queryParameters: queryParameters).toString();
  }

  static String _trimTrailingSlash(String value) {
    var v = value.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}
