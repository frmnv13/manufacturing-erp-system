class BankMutationStudentMatch {
  final int id;
  final String nim;
  final String name;

  const BankMutationStudentMatch({
    required this.id,
    required this.nim,
    required this.name,
  });

  factory BankMutationStudentMatch.fromMap(Map<String, Object?> map) {
    return BankMutationStudentMatch(
      id: _toInt(map['id']),
      nim: map['nim']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}

class BankMutationInvoiceMatch {
  final int id;
  final int amountDue;
  final String status;
  final String paymentTypeName;

  const BankMutationInvoiceMatch({
    required this.id,
    required this.amountDue,
    required this.status,
    required this.paymentTypeName,
  });

  factory BankMutationInvoiceMatch.fromMap(Map<String, Object?> map) {
    return BankMutationInvoiceMatch(
      id: _toInt(map['id']),
      amountDue: _toInt(map['amountDue']),
      status: map['status']?.toString() ?? '',
      paymentTypeName: map['paymentTypeName']?.toString() ?? '',
    );
  }
}

class BankMutationItem {
  final int id;
  final DateTime? mutationDate;
  final String description;
  final int amount;
  final bool isCredit;
  final String referenceNo;
  final String sourceFile;
  final String matchStatus;
  final double confidence;
  final DateTime? reviewedAt;
  final BankMutationStudentMatch? matchedStudent;
  final BankMutationInvoiceMatch? matchedInvoice;
  final String matchReason;
  final String parsedNim;

  const BankMutationItem({
    required this.id,
    required this.mutationDate,
    required this.description,
    required this.amount,
    required this.isCredit,
    required this.referenceNo,
    required this.sourceFile,
    required this.matchStatus,
    required this.confidence,
    required this.reviewedAt,
    required this.matchedStudent,
    required this.matchedInvoice,
    required this.matchReason,
    required this.parsedNim,
  });

  factory BankMutationItem.fromMap(Map<String, Object?> map) {
    final matchedStudentRaw = map['matchedStudent'];
    final matchedInvoiceRaw = map['matchedInvoice'];
    final rawPayload = map['rawPayload'];
    final payloadMap = rawPayload is Map
        ? _toStringMap(rawPayload)
        : const <String, Object?>{};
    final parsedNim = _extractNestedString(payloadMap, ['parsedNim']);
    final matchReason = _extractNestedString(payloadMap, ['matchReason']);

    return BankMutationItem(
      id: _toInt(map['id']),
      mutationDate: _toDateTime(map['mutationDate']),
      description: map['description']?.toString() ?? '',
      amount: _toInt(map['amount']),
      isCredit: map['isCredit'] == true,
      referenceNo: map['referenceNo']?.toString() ?? '',
      sourceFile: map['sourceFile']?.toString() ?? '',
      matchStatus: map['matchStatus']?.toString() ?? 'unmatched',
      confidence: _toDouble(map['confidence']),
      reviewedAt: _toDateTime(map['reviewedAt']),
      matchedStudent: matchedStudentRaw is Map
          ? BankMutationStudentMatch.fromMap(_toStringMap(matchedStudentRaw))
          : null,
      matchedInvoice: matchedInvoiceRaw is Map
          ? BankMutationInvoiceMatch.fromMap(_toStringMap(matchedInvoiceRaw))
          : null,
      matchReason: matchReason,
      parsedNim: parsedNim,
    );
  }
}

class BankMutationListResult {
  final List<BankMutationItem> items;
  final Map<String, int> counts;

  const BankMutationListResult({required this.items, required this.counts});
}

class BankMutationImportRow {
  final DateTime? mutationDate;
  final String description;
  final int amount;
  final bool isCredit;
  final String referenceNo;
  final String bankAccount;

  const BankMutationImportRow({
    required this.mutationDate,
    required this.description,
    required this.amount,
    required this.isCredit,
    required this.referenceNo,
    required this.bankAccount,
  });

  Map<String, Object?> toMap() {
    return {
      'mutationDate': mutationDate?.toIso8601String(),
      'description': description,
      'amount': amount,
      'isCredit': isCredit,
      if (referenceNo.trim().isNotEmpty) 'referenceNo': referenceNo.trim(),
      if (bankAccount.trim().isNotEmpty) 'bankAccount': bankAccount.trim(),
    };
  }
}

class BankMutationImportResult {
  final int imported;
  final int skipped;
  final int duplicates;
  final int matched;
  final int candidate;
  final int unmatched;

  const BankMutationImportResult({
    required this.imported,
    required this.skipped,
    required this.duplicates,
    required this.matched,
    required this.candidate,
    required this.unmatched,
  });

  factory BankMutationImportResult.fromMap(Map<String, Object?> map) {
    return BankMutationImportResult(
      imported: _toInt(map['imported']),
      skipped: _toInt(map['skipped']),
      duplicates: _toInt(map['duplicates']),
      matched: _toInt(map['matched']),
      candidate: _toInt(map['candidate']),
      unmatched: _toInt(map['unmatched']),
    );
  }
}

class BankAutoMatchRule {
  final String id;
  final String name;
  final String bankAccountPattern;
  final String majorLabel;
  final String descriptionRegex;
  final int nimCaptureGroup;
  final String bankAccountOverride;
  final String prependText;
  final bool isEnabled;

  const BankAutoMatchRule({
    required this.id,
    required this.name,
    this.bankAccountPattern = '',
    this.majorLabel = '',
    this.descriptionRegex = '',
    this.nimCaptureGroup = 1,
    this.bankAccountOverride = '',
    this.prependText = '',
    this.isEnabled = true,
  });

  BankAutoMatchRule copyWith({
    String? id,
    String? name,
    String? bankAccountPattern,
    String? majorLabel,
    String? descriptionRegex,
    int? nimCaptureGroup,
    String? bankAccountOverride,
    String? prependText,
    bool? isEnabled,
  }) {
    return BankAutoMatchRule(
      id: id ?? this.id,
      name: name ?? this.name,
      bankAccountPattern: bankAccountPattern ?? this.bankAccountPattern,
      majorLabel: majorLabel ?? this.majorLabel,
      descriptionRegex: descriptionRegex ?? this.descriptionRegex,
      nimCaptureGroup: nimCaptureGroup ?? this.nimCaptureGroup,
      bankAccountOverride: bankAccountOverride ?? this.bankAccountOverride,
      prependText: prependText ?? this.prependText,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'bankAccountPattern': bankAccountPattern,
      'majorLabel': majorLabel,
      'descriptionRegex': descriptionRegex,
      'nimCaptureGroup': nimCaptureGroup,
      'bankAccountOverride': bankAccountOverride,
      'prependText': prependText,
      'isEnabled': isEnabled,
    };
  }

  factory BankAutoMatchRule.fromMap(Map<String, Object?> map) {
    final id = map['id']?.toString().trim() ?? '';
    final name = map['name']?.toString().trim() ?? '';
    final normalizedId = id.isEmpty
        ? 'rule-${DateTime.now().millisecondsSinceEpoch}'
        : id;
    final normalizedName = name.isEmpty ? 'Rule Auto-Match' : name;

    return BankAutoMatchRule(
      id: normalizedId,
      name: normalizedName,
      bankAccountPattern: map['bankAccountPattern']?.toString() ?? '',
      majorLabel: map['majorLabel']?.toString() ?? '',
      descriptionRegex: map['descriptionRegex']?.toString() ?? '',
      nimCaptureGroup: _normalizePositiveInt(
        map['nimCaptureGroup'],
        fallback: 1,
      ),
      bankAccountOverride: map['bankAccountOverride']?.toString() ?? '',
      prependText: map['prependText']?.toString() ?? '',
      isEnabled: map['isEnabled'] == null ? true : map['isEnabled'] == true,
    );
  }
}

Map<String, Object?> _toStringMap(Map input) {
  return input.map((key, value) => MapEntry(key.toString(), value));
}

String _extractNestedString(Map<String, Object?> map, List<String> path) {
  Object? current = map;
  for (final key in path) {
    if (current is! Map) {
      return '';
    }
    current = current[key];
  }
  return current?.toString() ?? '';
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

double _toDouble(Object? raw) {
  if (raw is double) {
    return raw;
  }
  if (raw is int) {
    return raw.toDouble();
  }
  return double.tryParse(raw?.toString() ?? '') ?? 0;
}

DateTime? _toDateTime(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

int _normalizePositiveInt(Object? raw, {required int fallback}) {
  final value = _toInt(raw);
  if (value <= 0) {
    return fallback;
  }
  return value;
}
