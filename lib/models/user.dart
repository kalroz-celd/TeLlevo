class User {
  final int id;
  final String name;
  final String email;
  final String avatar;
  final List<String> roles;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.avatar,
    required this.roles,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final rolesJson = json['roles'] as List? ?? const [];

    // Try several fields for id: common names used by different backends.
    int parseId(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      final s = value.toString().replaceAll('.', '').replaceAll(',', '');
      return int.tryParse(s) ?? 0;
    }

    final idCandidates = [
      json['id'],
      json['user_id'],
      json['driver_id'],
      json['ci'],
    ];
    int resolvedId = 0;
    for (final cand in idCandidates) {
      final v = parseId(cand);
      if (v != 0) {
        resolvedId = v;
        break;
      }
    }

    return User(
      id: resolvedId,
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      roles: rolesJson.map((r) => r.toString()).toList(),
    );
  }

  bool hasRole(String role) => roles.contains(role);
}
