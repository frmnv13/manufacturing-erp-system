import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/admin_models.dart';

class RemoteAdminApi {
  final String baseUrl;
  final http.Client _client;

  RemoteAdminApi({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory RemoteAdminApi.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('API_BASE_URL');
    return RemoteAdminApi(baseUrl: rawBaseUrl.trim());
  }

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/auth/change-password');
    final response = await _client.post(
      uri,
      headers: _headers(token: token),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    _throwIfError(response, fallback: 'Gagal mengubah password.');
  }

  Future<List<AdminUserAccount>> fetchUsers({
    required String token,
  }) async {
    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/users');
    final response = await _client.get(
      uri,
      headers: _headers(token: token),
    );
    _throwIfError(response, fallback: 'Gagal mengambil data user.');

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons users tidak valid.');
    }
    final items = decoded['items'];
    if (items is! List) {
      return const [];
    }

    final result = <AdminUserAccount>[];
    for (final item in items) {
      if (item is Map) {
        result.add(AdminUserAccount.fromMap(_toStringMap(item)));
      }
    }
    return result;
  }

  Future<void> createUser({
    required String token,
    required String username,
    required String fullName,
    required String password,
    required String role,
    required bool isActive,
  }) async {
    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/users');
    final response = await _client.post(
      uri,
      headers: _headers(token: token),
      body: jsonEncode({
        'username': username.trim(),
        'fullName': fullName.trim(),
        'password': password,
        'role': role.trim(),
        'isActive': isActive,
      }),
    );
    _throwIfError(response, fallback: 'Gagal membuat user baru.');
  }

  Future<void> updateUser({
    required String token,
    required int userId,
    String? fullName,
    String? role,
    bool? isActive,
  }) async {
    final body = <String, Object?>{};
    if (fullName != null) {
      body['fullName'] = fullName.trim();
    }
    if (role != null) {
      body['role'] = role.trim();
    }
    if (isActive != null) {
      body['isActive'] = isActive;
    }

    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/users/$userId');
    final response = await _client.put(
      uri,
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    _throwIfError(response, fallback: 'Gagal mengubah user.');
  }

  Future<List<AdminAuditLog>> fetchAuditLogs({
    required String token,
    int limit = 100,
  }) async {
    final normalizedLimit = limit < 1 ? 1 : (limit > 500 ? 500 : limit);
    final uri = Uri.parse(
      '${_normalizeBaseUrl(baseUrl)}/api/audit-logs?limit=$normalizedLimit',
    );
    final response = await _client.get(
      uri,
      headers: _headers(token: token),
    );
    _throwIfError(response, fallback: 'Gagal mengambil audit log.');

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons audit log tidak valid.');
    }

    final items = decoded['items'];
    if (items is! List) {
      return const [];
    }

    final result = <AdminAuditLog>[];
    for (final item in items) {
      if (item is Map) {
        result.add(AdminAuditLog.fromMap(_toStringMap(item)));
      }
    }
    return result;
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

  void _throwIfError(http.Response response, {required String fallback}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw StateError(
      _extractErrorMessage(
        response.body,
        fallback: '$fallback (${response.statusCode}).',
      ),
    );
  }

  String _extractErrorMessage(String raw, {required String fallback}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {
      // Ignore parsing issues and fallback to generic message.
    }
    return fallback;
  }
}

Map<String, Object?> _toStringMap(Map input) {
  return input.map((key, value) => MapEntry(key.toString(), value));
}
