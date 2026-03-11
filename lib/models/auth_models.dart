class AuthUser {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final int officeId;
  final String officeCode;
  final String officeName;

  const AuthUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.officeId,
    required this.officeCode,
    required this.officeName,
  });

  factory AuthUser.fromMap(Map<String, Object?> map) {
    final officeRaw = map['office'];
    final office = officeRaw is Map ? _toStringMap(officeRaw) : const <String, Object?>{};

    return AuthUser(
      id: _toInt(map['id']),
      username: map['username']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
      officeId: _toInt(office['id']),
      officeCode: office['code']?.toString() ?? '',
      officeName: office['name']?.toString() ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'username': username,
      'fullName': fullName,
      'role': role,
      'office': {
        'id': officeId,
        'code': officeCode,
        'name': officeName,
      },
    };
  }
}

class AuthSession {
  final String token;
  final String tokenType;
  final DateTime? expiresAt;
  final AuthUser user;

  const AuthSession({
    required this.token,
    required this.tokenType,
    required this.expiresAt,
    required this.user,
  });

  factory AuthSession.fromMap(Map<String, Object?> map) {
    final userRaw = map['user'];
    final userMap =
        userRaw is Map ? _toStringMap(userRaw) : const <String, Object?>{};

    return AuthSession(
      token: map['token']?.toString() ?? '',
      tokenType: map['tokenType']?.toString() ?? 'Bearer',
      expiresAt: _toDateTime(map['expiresAt']),
      user: AuthUser.fromMap(userMap),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'token': token,
      'tokenType': tokenType,
      'expiresAt': expiresAt?.toIso8601String(),
      'user': user.toMap(),
    };
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

DateTime? _toDateTime(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
