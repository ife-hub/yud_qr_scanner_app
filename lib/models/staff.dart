/// An admin/operator account (assets/admins.json).
class Staff {
  final String id;
  final String username;
  final String password;
  final String name;
  final String role;
  final String group;
  final String specialRole; // '', 'attendance_leaders', or 'super_admin'

  Staff({
    required this.id,
    required this.username,
    required this.password,
    required this.name,
    required this.role,
    required this.group,
    required this.specialRole,
  });

  factory Staff.fromMap(Map<String, dynamic> map) {
    return Staff(
      id: map['id'] as String,
      username: map['username'] as String,
      password: map['password'] as String,
      name: map['name'] as String,
      role: map['role'] as String,
      group: map['group'] as String,
      specialRole: (map['specialRole'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'name': name,
      'role': role,
      'group': group,
      'specialRole': specialRole,
    };
  }

  bool get isSuperAdmin => specialRole == 'super_admin';
  bool get canScanLeaders => isSuperAdmin || specialRole == 'attendance_leaders';

  /// Whether this admin can hand out Radios/Earpieces or Bowls/Baskets.
  bool get canHandleResources => isSuperAdmin || specialRole == 'operations';

  /// Whether this admin can check in [member] for General Attendance -
  /// super_admin bypasses the group-match requirement.
  bool canCheckInMember(String memberGroup) => isSuperAdmin || group == memberGroup;
}