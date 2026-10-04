class SessionUser {
  const SessionUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.roles,
    required this.roleNames,
    required this.permissions,
    this.employeeId,
  });

  final int id;
  final String email;
  final String fullName;
  final bool isActive;
  final int? employeeId;
  final List<String> roles;
  final List<String> roleNames;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  bool canAny(Iterable<String> candidates) =>
      candidates.any(permissions.contains);

  bool get isSuperAdmin => roles.contains('super_admin');

  String get primaryRole => roleNames.isEmpty ? 'Team member' : roleNames.first;

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      id: _intValue(json['id']),
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? 'Team member',
      isActive: json['is_active'] == true || json['is_active'] == 1,
      employeeId: json['employee_id'] == null ? null : _intValue(json['employee_id']),
      roles: _stringList(json['roles']),
      roleNames: _stringList(json['role_names']),
      permissions: _stringList(json['permissions']).toSet(),
    );
  }
}

int _intValue(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).toList(growable: false);
}
