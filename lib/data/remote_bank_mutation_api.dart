import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/bank_mutation_models.dart';

class RemoteBankMutationApi {
  final String baseUrl;
  final http.Client _client;

  RemoteBankMutationApi({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory RemoteBankMutationApi.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('API_BASE_URL');
    return RemoteBankMutationApi(baseUrl: rawBaseUrl.trim());
  }

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<BankMutationListResult> fetchMutations({
    required String token,
    String status = '',
    int limit = 200,
  }) async {
    final cappedLimit = limit < 1 ? 1 : (limit > 500 ? 500 : limit);
    final params = <String, String>{
      'limit': cappedLimit.toString(),
    };
    final normalizedStatus = status.trim();
    if (normalizedStatus.isNotEmpty) {
      params['status'] = normalizedStatus;
    }

    final uri = Uri.parse(
      '${_normalizeBaseUrl(baseUrl)}/api/bank-mutations',
    ).replace(queryParameters: params);
    final response = await _client.get(
      uri,
      headers: _headers(token: token),
    );
    _throwIfError(response, fallback: 'Gagal mengambil data mutasi bank.');

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons mutasi bank tidak valid.');
    }

    final itemsRaw = decoded['items'];
    final resultItems = <BankMutationItem>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map) {
          resultItems.add(BankMutationItem.fromMap(_toStringMap(item)));
        }
      }
    }

    final countsRaw = decoded['counts'];
    final counts = <String, int>{
      'unmatched': 0,
      'candidate': 0,
      'matched': 0,
      'approved': 0,
      'rejected': 0,
    };
    if (countsRaw is Map) {
      for (final entry in countsRaw.entries) {
        final key = entry.key.toString();
        if (counts.containsKey(key)) {
          counts[key] = _toInt(entry.value);
        }
      }
    }

    return BankMutationListResult(
      items: resultItems,
      counts: counts,
    );
  }

  Future<BankMutationImportResult> importRows({
    required String token,
    required List<BankMutationImportRow> rows,
    String sourceFile = '',
  }) async {
    final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/bank-mutations/import');
    final response = await _client.post(
      uri,
      headers: _headers(token: token),
      body: jsonEncode({
        'sourceFile': sourceFile.trim(),
        'rows': rows.map((item) => item.toMap()).toList(),
      }),
    );
    _throwIfError(response, fallback: 'Gagal import mutasi bank.');

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons import mutasi tidak valid.');
    }
    final summaryRaw = decoded['summary'];
    if (summaryRaw is! Map) {
      throw const FormatException('Summary import mutasi tidak valid.');
    }
    return BankMutationImportResult.fromMap(_toStringMap(summaryRaw));
  }

  Future<void> approveMutation({
    required String token,
    required int mutationId,
    int? invoiceId,
  }) async {
    final uri = Uri.parse(
      '${_normalizeBaseUrl(baseUrl)}/api/bank-mutations/$mutationId/approve',
    );
    final body = <String, Object?>{};
    if (invoiceId != null && invoiceId > 0) {
      body['invoiceId'] = invoiceId;
    }
    final response = await _client.post(
      uri,
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    _throwIfError(response, fallback: 'Gagal approve mutasi.');
  }

  Future<void> rejectMutation({
    required String token,
    required int mutationId,
  }) async {
    final uri = Uri.parse(
      '${_normalizeBaseUrl(baseUrl)}/api/bank-mutations/$mutationId/reject',
    );
    final response = await _client.post(
      uri,
      headers: _headers(token: token),
      body: '{}',
    );
    _throwIfError(response, fallback: 'Gagal reject mutasi.');
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

int _toInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is double) {
    return raw.toInt();
  }
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}
