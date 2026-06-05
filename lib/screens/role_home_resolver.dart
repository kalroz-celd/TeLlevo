import 'package:flutter/material.dart';
import 'package:tellevo/screens/administrator_main_screen.dart';
import 'package:tellevo/screens/driver_main_screen.dart';
import 'package:tellevo/screens/passenger_main_screen.dart';

Widget resolveHomeForRoles(List<String> roles) {
  final normalizedRoles =
      roles
          .map((role) => role.trim().toLowerCase())
          .where((role) => role.isNotEmpty)
          .toSet();

  if (_hasAnyRole(normalizedRoles, const {'administrator', 'superadmin'})) {
    return const AdministratorMainScreen();
  }

  if (_hasAnyRole(normalizedRoles, const {'driver', 'admin'})) {
    return const DriverMainScreen();
  }

  if (_hasAnyRole(normalizedRoles, const {'passenger'})) {
    return const PassengerMainScreen();
  }

  return const _UnauthorizedRoleScreen();
}

bool _hasAnyRole(Set<String> roles, Set<String> allowedRoles) {
  return allowedRoles.any(roles.contains);
}

class _UnauthorizedRoleScreen extends StatelessWidget {
  const _UnauthorizedRoleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 52),
              const SizedBox(height: 12),
              Text(
                'Rol no autorizado',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'No hay una vista asignada para este perfil todavía.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
