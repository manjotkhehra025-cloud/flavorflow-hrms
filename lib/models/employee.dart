enum UserRole { employee, admin }

extension UserRoleX on UserRole {
  String get label => this == UserRole.admin ? 'Admin / HR' : 'Employee';
}

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.department,
    required this.designation,
    required this.joiningDate,
    required this.monthlyCtc,
    this.role = UserRole.employee,
    this.managerName,
    this.address,
    this.bloodGroup,
    this.isActive = true,
  });

  /// Employee code used to log in, e.g. EMP001.
  final String id;
  final String name;
  final String email;
  final String phone;
  final String department;
  final String designation;
  final DateTime joiningDate;

  /// Monthly gross salary in INR (used by the mock payslip generator).
  final double monthlyCtc;
  final UserRole role;
  final String? managerName;
  final String? address;
  final String? bloodGroup;
  final bool isActive;

  bool get isAdmin => role == UserRole.admin;

  String get firstName => name.split(' ').first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Employee copyWith({
    String? name,
    String? email,
    String? phone,
    String? department,
    String? designation,
    DateTime? joiningDate,
    double? monthlyCtc,
    UserRole? role,
    String? managerName,
    String? address,
    String? bloodGroup,
    bool? isActive,
  }) {
    return Employee(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      department: department ?? this.department,
      designation: designation ?? this.designation,
      joiningDate: joiningDate ?? this.joiningDate,
      monthlyCtc: monthlyCtc ?? this.monthlyCtc,
      role: role ?? this.role,
      managerName: managerName ?? this.managerName,
      address: address ?? this.address,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'department': department,
        'designation': designation,
        'joiningDate': joiningDate.toIso8601String(),
        'monthlyCtc': monthlyCtc,
        'role': role.name,
        'managerName': managerName,
        'address': address,
        'bloodGroup': bloodGroup,
        'isActive': isActive,
      };

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        department: json['department'] as String? ?? '',
        designation: json['designation'] as String? ?? '',
        joiningDate: DateTime.parse(json['joiningDate'] as String),
        monthlyCtc: (json['monthlyCtc'] as num?)?.toDouble() ?? 0,
        role: UserRole.values.byName(json['role'] as String? ?? 'employee'),
        managerName: json['managerName'] as String?,
        address: json['address'] as String?,
        bloodGroup: json['bloodGroup'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );
}
