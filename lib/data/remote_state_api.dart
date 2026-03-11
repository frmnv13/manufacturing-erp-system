import 'dart:convert';

import 'package:http/http.dart' as http;

class RemoteStateApi {
  final String baseUrl;
  final String token;
  final http.Client _client;
  String? _tokenOverride;

  RemoteStateApi({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory RemoteStateApi.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('API_BASE_URL');
    const rawToken = String.fromEnvironment('API_TOKEN');
    return RemoteStateApi(
      baseUrl: rawBaseUrl.trim(),
      token: rawToken.trim(),
    );
  }

  bool get isConfigured => baseUrl.isNotEmpty;

  void setTokenOverride(String? tokenValue) {
    final normalized = tokenValue?.trim() ?? '';
    _tokenOverride = normalized.isEmpty ? null : normalized;
  }

  Future<Map<String, Object?>?> fetchState() async {
    if (!isConfigured) {
      return null;
    }

    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/state');
    final response = await _client.get(uri, headers: _buildHeaders());

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Gagal mengambil state dari API (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons API tidak valid.');
    }

    final data = decoded['data'];
    if (data == null) {
      return null;
    }
    if (data is! Map) {
      throw const FormatException('Payload state API tidak valid.');
    }

    final map = <String, Object?>{};
    for (final entry in data.entries) {
      map[entry.key.toString()] = entry.value;
    }
    return map;
  }

  Future<void> pushState(Map<String, Object?> state) async {
    if (!isConfigured) {
      return;
    }

    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/state');
    final response = await _client.put(
      uri,
      headers: _buildHeaders(),
      body: jsonEncode({'data': state}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Gagal menyimpan state ke API (${response.statusCode}).');
    }
  }

  Map<String, String> _buildHeaders() {
    final authToken = _tokenOverride ?? token;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  String _normalizeBaseUrl(String raw) {
    final normalized = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    return normalized;
  }
}
