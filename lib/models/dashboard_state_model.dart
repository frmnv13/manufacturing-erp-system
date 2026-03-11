import 'bank_mutation_models.dart';
import 'finance_models.dart';

class DashboardStateModel {
  final int selectedIndex;
  final int ledgerBalance;
  final int? realBalance;
  final bool autoReconcileEnabled;
  final bool strictPrerequisiteValidation;
  final bool allowManualSettlementOverride;
  final bool notifyDifferenceOnDashboard;
  final String operatorName;
  final List<PaymentType> paymentTypes;
  final List<StudentAccount> students;
  final List<FinanceTransaction> transactions;
  final List<BankAutoMatchRule> bankAutoMatchRules;

  const DashboardStateModel({
    required this.selectedIndex,
    required this.ledgerBalance,
    required this.realBalance,
    required this.autoReconcileEnabled,
    required this.strictPrerequisiteValidation,
    required this.allowManualSettlementOverride,
    required this.notifyDifferenceOnDashboard,
    required this.operatorName,
    required this.paymentTypes,
    required this.students,
    required this.transactions,
    required this.bankAutoMatchRules,
  });

  Map<String, Object?> toMap() {
    return {
      'selectedIndex': selectedIndex,
      'ledgerBalance': ledgerBalance,
      'realBalance': realBalance,
      'autoReconcileEnabled': autoReconcileEnabled,
      'strictPrerequisiteValidation': strictPrerequisiteValidation,
      'allowManualSettlementOverride': allowManualSettlementOverride,
      'notifyDifferenceOnDashboard': notifyDifferenceOnDashboard,
      'operatorName': operatorName,
      'paymentTypes': paymentTypes.map((item) => item.toMap()).toList(),
      'students': students.map((item) => item.toMap()).toList(),
      'transactions': transactions.map((item) => item.toMap()).toList(),
      'bankAutoMatchRules': bankAutoMatchRules
          .map((item) => item.toMap())
          .toList(),
    };
  }

  factory DashboardStateModel.fromMap(
    Map<String, Object?> map, {
    required DashboardStateModel fallback,
  }) {
    final paymentTypeMaps =
        (map['paymentTypes'] as List<dynamic>? ?? const <dynamic>[]);
    final studentMaps =
        (map['students'] as List<dynamic>? ?? const <dynamic>[]);
    final transactionMaps =
        (map['transactions'] as List<dynamic>? ?? const <dynamic>[]);
    final bankRuleMaps =
        (map['bankAutoMatchRules'] as List<dynamic>? ?? const <dynamic>[]);

    final paymentTypes = paymentTypeMaps
        .whereType<Map>()
        .map((item) => PaymentType.fromMap(_asStringMap(item)))
        .toList();
    final students = studentMaps
        .whereType<Map>()
        .map((item) => StudentAccount.fromMap(_asStringMap(item)))
        .toList();
    final transactions = transactionMaps
        .whereType<Map>()
        .map((item) => FinanceTransaction.fromMap(_asStringMap(item)))
        .toList();
    final bankAutoMatchRules = bankRuleMaps
        .whereType<Map>()
        .map((item) => BankAutoMatchRule.fromMap(_asStringMap(item)))
        .toList();
    final hasBankRules = map.containsKey('bankAutoMatchRules');

    return DashboardStateModel(
      selectedIndex: _toInt(map['selectedIndex'], fallback.selectedIndex),
      ledgerBalance: _toInt(map['ledgerBalance'], fallback.ledgerBalance),
      realBalance: _toNullableInt(map['realBalance']),
      autoReconcileEnabled: _toBool(
        map['autoReconcileEnabled'],
        fallback.autoReconcileEnabled,
      ),
      strictPrerequisiteValidation: _toBool(
        map['strictPrerequisiteValidation'],
        fallback.strictPrerequisiteValidation,
      ),
      allowManualSettlementOverride: _toBool(
        map['allowManualSettlementOverride'],
        fallback.allowManualSettlementOverride,
      ),
      notifyDifferenceOnDashboard: _toBool(
        map['notifyDifferenceOnDashboard'],
        fallback.notifyDifferenceOnDashboard,
      ),
      operatorName: map['operatorName']?.toString().trim().isNotEmpty == true
          ? map['operatorName']!.toString()
          : fallback.operatorName,
      paymentTypes: paymentTypes.isEmpty ? fallback.paymentTypes : paymentTypes,
      students: students.isEmpty ? fallback.students : students,
      transactions: transactions.isEmpty ? fallback.transactions : transactions,
      bankAutoMatchRules: hasBankRules
          ? bankAutoMatchRules
          : fallback.bankAutoMatchRules,
    );
  }
}

Map<String, Object?> _asStringMap(Map input) {
  return input.map((key, value) => MapEntry(key.toString(), value));
}

int _toInt(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
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

bool _toBool(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    if (value.toLowerCase() == 'true') {
      return true;
    }
    if (value.toLowerCase() == 'false') {
      return false;
    }
  }
  return fallback;
}
