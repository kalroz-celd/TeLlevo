class UserProfile {
  final int id;
  final String name;
  final String lastName;
  final String email;
  final String? photoUrl;
  final String ci;    // RUT: cuerpo (sin dígito verificador)
  final String digit; // dígito verificador (K posible)

  UserProfile({
    required this.id,
    required this.name,
    required this.lastName,
    required this.email,
    required this.ci,
    required this.digit,
    this.photoUrl,
  });

  // Helpers
  String get rut => '$ci-$digit';
  String get fullName =>
      [name, lastName].where((s) => s.trim().isNotEmpty).join(' ');

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => (v ?? '').toString();

    // name y lastname robustos (soporta varias claves)
    final rawName = s(json['name'] ?? json['first_name'] ?? json['nombre']);
    final rawLast = s(
      json['last_name'] ??
      json['lastname'] ??    // <- tu columna en BD/API
      json['surname'] ??
      json['apellidos'] ??
      json['apellido'] ??
      json['lastName']       // por si viene en camelCase
    );

    final rawCi = s(json['ci'] ?? json['rut'] ?? json['rut_body']);
    final rawDv = s(json['digit'] ?? json['dv'] ?? json['rut_dv']);

    final rawPhoto = s(json['photo'] ??
        json['photo_url'] ??
        json['avatar'] ??
        json['image'] ??
        json['profile_photo_path'] ??
        json['photoUrl']);

    return UserProfile(
      id: int.tryParse(s(json['id'])) ?? 0,
      name: rawName,
      lastName: rawLast,
      email: s(json['email']),
      ci: rawCi,
      digit: rawDv,
      photoUrl: rawPhoto.isEmpty ? null : rawPhoto,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'last_name': lastName, // puedes enviar como last_name
        'email': email,
        'ci': ci,
        'digit': digit,
        'photo_url': photoUrl,
      };
}
