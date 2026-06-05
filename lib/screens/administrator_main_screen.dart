import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/services/auth.dart';

class AdministratorMainScreen extends StatelessWidget {
  const AdministratorMainScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<Auth>().logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<Auth>();
    final user = auth.user;
    final avatar = auth.avatarUrl();
    final displayName =
        user.name.trim().isEmpty ? 'Administrador' : user.name.trim();
    final roles =
        user.roles.where((role) => role.trim().isNotEmpty).toList(growable: false);

    const modules = [
      (
        title: 'Gestión de usuarios',
        subtitle: 'Espacio reservado para administrar accesos, perfiles y permisos.',
        icon: Icons.group_rounded,
        color: Color(0xFF0F766E),
      ),
      (
        title: 'Operación diaria',
        subtitle: 'Aquí podremos incorporar tableros, métricas y acciones críticas.',
        icon: Icons.route_rounded,
        color: Color(0xFF1D4ED8),
      ),
      (
        title: 'Reportes',
        subtitle: 'Vista prevista para indicadores, estados y seguimiento histórico.',
        icon: Icons.insert_chart_rounded,
        color: Color(0xFFB45309),
      ),
      (
        title: 'Configuración',
        subtitle: 'Zona preparada para parámetros globales y opciones del sistema.',
        icon: Icons.tune_rounded,
        color: Color(0xFF7C3AED),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.secundary,
                    const Color(0xFF0F4C64),
                    AppColors.primary,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(36),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withOpacity(.18),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.admin_panel_settings_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Panel Administrador',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => _logout(context),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.secundary,
                              shape: const StadiumBorder(),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Salir'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 700;
                          final infoColumn = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Centro de administración',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      height: 1.05,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Esta vista queda separada de conductor y pasajero. '
                                'La base ya está lista para comenzar a montar los módulos del nuevo perfil Administrador.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: Colors.white.withOpacity(.88),
                                      height: 1.45,
                                    ),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _InfoBadge(
                                    icon: Icons.person_rounded,
                                    label: displayName,
                                  ),
                                  if (user.email.trim().isNotEmpty)
                                    _InfoBadge(
                                      icon: Icons.mail_outline_rounded,
                                      label: user.email.trim(),
                                    ),
                                  ...roles.map(
                                    (role) => _InfoBadge(
                                      icon: Icons.verified_user_rounded,
                                      label: role,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );

                          return Flex(
                            direction: wide ? Axis.horizontal : Axis.vertical,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (wide) Expanded(flex: 3, child: infoColumn) else infoColumn,
                              SizedBox(width: wide ? 20 : 0, height: wide ? 0 : 20),
                              _AdminProfileCard(
                                name: displayName,
                                avatarUrl: avatar,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHeading(
                    overline: 'Base inicial',
                    title: 'Vista independiente preparada',
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.05),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF15803D),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'La estructura base del administrador ya existe',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cuando me indiques el siguiente paso, montamos aquí el contenido específico del nuevo perfil.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.black.withOpacity(.65),
                                          height: 1.45,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Siguiente espacio de trabajo',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Aquí construiremos las herramientas, métricas o formularios propios del Administrador.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _SectionHeading(
                    overline: 'Módulos',
                    title: 'Bloques reservados para crecer esta vista',
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: modules.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: wide ? 2 : 1,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: wide ? 1.5 : 1.18,
                        ),
                        itemBuilder: (context, index) {
                          final module = modules[index];
                          return _AdminModuleCard(
                            title: module.title,
                            subtitle: module.subtitle,
                            icon: module.icon,
                            color: module.color,
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminProfileCard extends StatelessWidget {
  const _AdminProfileCard({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  String get _initials {
    final parts =
        name.split(RegExp(r'\s+')).where((part) => part.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'AD';
    if (parts.length == 1) {
      final first = parts.first;
      return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withOpacity(.16),
            backgroundImage:
                avatarUrl != null && avatarUrl!.isNotEmpty
                    ? NetworkImage(avatarUrl!)
                    : null,
            child:
                avatarUrl == null || avatarUrl!.isEmpty
                    ? Text(
                      _initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                    : null,
          ),
          const SizedBox(height: 14),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Acceso administrativo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.overline, required this.title});

  final String overline;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          overline.toUpperCase(),
          style: const TextStyle(
            color: AppColors.secundary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _AdminModuleCard extends StatelessWidget {
  const _AdminModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Próximamente',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
              height: 1.45,
            ),
          ),
          const Spacer(),
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.arrow_outward_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                'Bloque listo para implementar',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
