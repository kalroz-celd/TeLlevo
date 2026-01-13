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

    return User(
      id:
          json['id'] is int
              ? json['id']
              : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      roles: rolesJson.map((r) => r.toString()).toList(),
    );
  }

  bool hasRole(String role) => roles.contains(role);
}
