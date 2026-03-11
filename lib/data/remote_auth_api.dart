import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';

class RemoteAuthApi {
  final String baseUrl;
  final http.Client _client;

  RemoteAuthApi({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory RemoteAuthApi.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('API_BASE_URL');
    return RemoteAuthApi(baseUrl: rawBaseUrl.trim());
  }

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<AuthSession> login({
    required String username,
    required String password,
    String officeCode = '',
  }) async {
    if (!isConfigured) {
      throw StateError('API_BASE_URL belum dikonfigurasi.');
    }

    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/auth/login');
    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode({
        'username': username.trim(),
        'password': password,
        if (officeCode.trim().isNotEmpty) 'officeCode': officeCode.trim(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_extractErrorMessage(
        response.body,
        fallback: 'Login gagal (${response.statusCode}).',
      ));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons login tidak valid.');
    }

    final map = <String, Object?>{};
    for (final entry in decoded.entries) {
      map[entry.key] = entry.value;
    }
    return AuthSession.fromMap(map);
  }

  Future<AuthUser> me(String token) async {
    if (!isConfigured) {
      throw StateError('API_BASE_URL belum dikonfigurasi.');
    }

    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/auth/me');
    final response = await _client.get(
      uri,
      headers: _headers(token: token),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_extractErrorMessage(
        response.body,
        fallback: 'Gagal mengambil profil (${response.statusCode}).',
      ));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons profil tidak valid.');
    }

    final userRaw = decoded['user'];
    if (userRaw is! Map) {
      throw const FormatException('Payload user tidak valid.');
    }
    final userMap = <String, Object?>{};
    for (final entry in userRaw.entries) {
      userMap[entry.key.toString()] = entry.value;
    }
    return AuthUser.fromMap(userMap);
  }

  Future<void> logout(String token) async {
    if (!isConfigured) {
      return;
    }

    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/auth/logout');
    final response = await _client.post(
      uri,
      headers: _headers(token: token),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_extractErrorMessage(
        response.body,
        fallback: 'Gagal logout (${response.statusCode}).',
      ));
    }
  }

  Map<String, String> _headers({String token = ''}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final cleanToken = token.trim();
    if (cleanToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $cleanToken';
    }
    return headers;
  }

  String _normalizeBaseUrl(String raw) {
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _extractErrorMessage(String raw, {required String fallback}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {
      // Ignore parsing issue and return fallback.
    }
    return fallback;
  }
}
