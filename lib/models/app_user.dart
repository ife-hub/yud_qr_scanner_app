/// A member of the roster (assets/members.json). `role` distinguishes a
/// regular attendee ("Member") from a leader ("Head" / "Ass. Head") -
/// leaders and members are the same underlying records, just filtered
/// differently depending on which scan purpose is being performed.
class AppUser {
  final String id;
  final String name;
  final String role; // "Member", "Head", "Ass. Head"
  final String group; // free-text team name, e.g. "Altar & Testimony Team"

  AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.group,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      name: map['name'] as String,
      role: map['role'] as String,
      group: map['group'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'role': role, 'group': group};
  }

  bool get isLeader => role != 'Member';
  bool get canCollectResources => role == 'Head' || role == 'Ass. Head';
}
