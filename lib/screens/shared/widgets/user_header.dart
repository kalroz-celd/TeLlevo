import 'package:flutter/material.dart';

class UserHeader extends StatelessWidget implements PreferredSizeWidget {
  final String name;       // ej: "Carlos Lagos"
  final String subtitle;   // ej: "correo@ejemplo.com"
  final String roleLabel;  // ej: "Pasajero"
  final String? photoUrl;
  final VoidCallback? onLogout;

  const UserHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.roleLabel,
    this.photoUrl,
    this.onLogout,
  });

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  // 👇 igualamos altura al header del conductor
  @override
  Size get preferredSize => const Size.fromHeight(180);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: preferredSize.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary, // fondo azul
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 40, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar circular con borde blanco
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child: (photoUrl == null || photoUrl!.isEmpty)
                    ? _InitialsAvatar(fallback: _initials(name))
                    : Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _InitialsAvatar(fallback: _initials(name)),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Info de usuario (alineado como en conductor)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "Rol: $roleLabel",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Botón Logout
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 28),
            tooltip: "Cerrar sesión",
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String fallback;
  const _InitialsAvatar({required this.fallback});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.25),
      child: Center(
        child: Text(
          fallback,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
