class AdminUserAccount {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final bool isActive;
  final int officeId;
  final String officeCode;
  final String officeName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdminUserAccount({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.officeId,
    required this.officeCode,
    required this.officeName,
    this.createdAt,
    this.updatedAt,
  });

  factory AdminUserAccount.fromMap(Map<String, Object?> map) {
    final officeRaw = map['office'];
    final officeMap =
        officeRaw is Map ? _toStringMap(officeRaw) : const <String, Object?>{};
    return AdminUserAccount(
      id: _toInt(map['id']),
      username: map['username']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
      isActive: _toBool(map['isActive'], defaultValue: true),
      officeId: _toInt(officeMap['id']),
      officeCode: officeMap['code']?.toString() ?? '',
      officeName: officeMap['name']?.toString() ?? '',
      createdAt: _toDateTime(map['createdAt']),
      updatedAt: _toDateTime(map['updatedAt']),
    );
  }
}

class AdminAuditLog {
  final int id;
  final String action;
  final String entityType;
  final String? entityId;
  final int? actorUserId;
  final String actorUsername;
  final Map<String, Object?>? payload;
  final DateTime? createdAt;

  const AdminAuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.actorUserId,
    required this.actorUsername,
    required this.payload,
    required this.createdAt,
  });

  factory AdminAuditLog.fromMap(Map<String, Object?> map) {
    final payloadRaw = map['payload'];
    final payloadMap =
        payloadRaw is Map ? _toStringMap(payloadRaw) : null;

    return AdminAuditLog(
      id: _toInt(map['id']),
      action: map['action']?.toString() ?? '',
      entityType: map['entityType']?.toString() ?? '',
      entityId: _toNullableString(map['entityId']),
      actorUserId: _toNullableInt(map['actorUserId']),
      actorUsername: map['actorUsername']?.toString() ?? '',
      payload: payloadMap,
      createdAt: _toDateTime(map['createdAt']),
    );
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

int? _toNullableInt(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    return raw;
  }
  if (raw is double) {
    return raw.toInt();
  }
  return int.tryParse(raw.toString());
}

bool _toBool(Object? raw, {required bool defaultValue}) {
  if (raw is bool) {
    return raw;
  }
  if (raw is int) {
    return raw != 0;
  }
  final value = raw?.toString().trim().toLowerCase() ?? '';
  if (value == '1' || value == 'true' || value == 'yes') {
    return true;
  }
  if (value == '0' || value == 'false' || value == 'no') {
    return false;
  }
  return defaultValue;
}

String? _toNullableString(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

DateTime? _toDateTime(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
