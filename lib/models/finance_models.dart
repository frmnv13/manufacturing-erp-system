class PaymentType {
  final String id;
  final String name;
  final int amount;
  final List<String> prerequisiteTypeIds;
  final int? targetSemester;
  final String? targetMajor;

  const PaymentType({
    required this.id,
    required this.name,
    required this.amount,
    this.prerequisiteTypeIds = const [],
    this.targetSemester,
    this.targetMajor,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'prerequisiteTypeIds': prerequisiteTypeIds,
      'targetSemester': targetSemester,
      'targetMajor': targetMajor,
    };
  }

  factory PaymentType.fromMap(Map<String, Object?> map) {
    final prerequisites =
        (map['prerequisiteTypeIds'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList();

    return PaymentType(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      amount: _toInt(map['amount']),
      prerequisiteTypeIds: prerequisites,
      targetSemester: _toNullableInt(map['targetSemester']),
      targetMajor: _toNullableTrimmedString(map['targetMajor']),
    );
  }
}

class StudentAccount {
  final String nim;
  final String name;
  final String major;
  final String className;
  final int semester;
  final int scholarshipPercent;
  final int installmentTerms;
  final Set<String> paidTypeIds;
  final Map<String, int> paidTypeAmounts;

  const StudentAccount({
    required this.nim,
    required this.name,
    required this.major,
    required this.className,
    required this.semester,
    this.scholarshipPercent = 0,
    this.installmentTerms = 1,
    this.paidTypeIds = const {},
    this.paidTypeAmounts = const {},
  });

  StudentAccount copyWith({
    String? nim,
    String? name,
    String? major,
    String? className,
    int? semester,
    int? scholarshipPercent,
    int? installmentTerms,
    Set<String>? paidTypeIds,
    Map<String, int>? paidTypeAmounts,
  }) {
    return StudentAccount(
      nim: nim ?? this.nim,
      name: name ?? this.name,
      major: major ?? this.major,
      className: className ?? this.className,
      semester: semester ?? this.semester,
      scholarshipPercent: scholarshipPercent ?? this.scholarshipPercent,
      installmentTerms: installmentTerms ?? this.installmentTerms,
      paidTypeIds: paidTypeIds ?? this.paidTypeIds,
      paidTypeAmounts: paidTypeAmounts ?? this.paidTypeAmounts,
    );
  }

  StudentAccount markPaid(String paymentTypeId) {
    return copyWith(paidTypeIds: {...paidTypeIds, paymentTypeId});
  }

  Map<String, Object?> toMap() {
    return {
      'nim': nim,
      'name': name,
      'major': major,
      'className': className,
      'semester': semester,
      'scholarshipPercent': scholarshipPercent,
      'installmentTerms': installmentTerms,
      'paidTypeIds': paidTypeIds.toList(),
      'paidTypeAmounts': paidTypeAmounts,
    };
  }

  factory StudentAccount.fromMap(Map<String, Object?> map) {
    final paidTypes = (map['paidTypeIds'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toSet();
    final paidTypeAmountsRaw = map['paidTypeAmounts'];
    final paidTypeAmounts = <String, int>{};
    if (paidTypeAmountsRaw is Map) {
      for (final entry in paidTypeAmountsRaw.entries) {
        paidTypeAmounts[entry.key.toString()] = _toInt(entry.value);
      }
    }

    return StudentAccount(
      nim: map['nim']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      major: map['major']?.toString() ?? '',
      className: map['className']?.toString() ?? '',
      semester: _toSemester(
        map['semester'],
        className: map['className']?.toString() ?? '',
      ),
      scholarshipPercent: _normalizeScholarshipPercent(
        map['scholarshipPercent'],
      ),
      installmentTerms: _normalizeInstallmentTerms(map['installmentTerms']),
      paidTypeIds: paidTypes,
      paidTypeAmounts: paidTypeAmounts,
    );
  }
}

enum FinanceTransactionStatus { completed, pending, failed }

class FinanceTransaction {
  final String category;
  final String description;
  final DateTime date;
  final int amount;
  final bool isIncome;
  final FinanceTransactionStatus status;
  final String? studentNim;
  final String? paymentTypeId;
  final String paymentMethod;

  const FinanceTransaction({
    required this.category,
    required this.description,
    required this.date,
    required this.amount,
    required this.isIncome,
    this.status = FinanceTransactionStatus.completed,
    this.studentNim,
    this.paymentTypeId,
    this.paymentMethod = 'manual',
  });

  Map<String, Object?> toMap() {
    return {
      'category': category,
      'description': description,
      'date': date.toIso8601String(),
      'amount': amount,
      'isIncome': isIncome,
      'status': status.name,
      'studentNim': studentNim,
      'paymentTypeId': paymentTypeId,
      'paymentMethod': paymentMethod,
    };
  }

  factory FinanceTransaction.fromMap(Map<String, Object?> map) {
    final rawDate = map['date']?.toString();
    final parsedDate = rawDate == null
        ? null
        : DateTime.tryParse(rawDate)?.toLocal();

    return FinanceTransaction(
      category: map['category']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      date: parsedDate ?? DateTime.now(),
      amount: _toInt(map['amount']),
      isIncome: map['isIncome'] == true,
      status: _statusFromName(map['status']?.toString()),
      studentNim: _toNullableTrimmedString(map['studentNim']),
      paymentTypeId: _toNullableTrimmedString(map['paymentTypeId']),
      paymentMethod: _toNullableTrimmedString(map['paymentMethod']) ?? 'manual',
    );
  }
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _toNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

int _toSemester(Object? raw, {required String className}) {
  final normalized = _toNullableInt(raw);
  if (normalized != null && normalized > 0) {
    return normalized;
  }

  final classMatch = RegExp(r'\d+').firstMatch(className);
  if (classMatch != null) {
    final parsed = int.tryParse(classMatch.group(0) ?? '');
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }

  return 1;
}

int _normalizeScholarshipPercent(Object? raw) {
  final value = _toInt(raw);
  if (value <= 0) {
    return 0;
  }
  if (value >= 100) {
    return 100;
  }

  const options = [0, 25, 50, 75, 100];
  var nearest = options.first;
  var minDistance = (value - nearest).abs();
  for (final option in options) {
    final distance = (value - option).abs();
    if (distance < minDistance) {
      minDistance = distance;
      nearest = option;
    }
  }
  return nearest;
}

int _normalizeInstallmentTerms(Object? raw) {
  final value = _toInt(raw);
  if (value <= 1) {
    return 1;
  }
  if (value > 12) {
    return 12;
  }
  return value;
}

String? _toNullableTrimmedString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

FinanceTransactionStatus _statusFromName(String? value) {
  for (final status in FinanceTransactionStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return FinanceTransactionStatus.completed;
}
