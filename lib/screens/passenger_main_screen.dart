import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tellevo/models/passenger_api.dart';
import 'package:tellevo/models/user_profile.dart';
import 'package:tellevo/services/dio.dart' as api;
import 'package:tellevo/screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:tellevo/services/auth.dart';

class PassengerMainScreen extends StatefulWidget {
  const PassengerMainScreen({super.key});

  @override
  State<PassengerMainScreen> createState() => _PassengerMainScreenState();
}

class _PassengerMainScreenState extends State<PassengerMainScreen> {
  late final PassengerApi _api;
  late Future<UserProfile> _future;

  @override
  void initState() {
    super.initState();
    _api = PassengerApi();
    _future = _api.fetchMe();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _api.fetchMe();
    });
  }

  String _buildQrPayload(UserProfile u) {
    final payload = {
      "type": "tellevo_passenger",
      "user_id": u.id,
      "name": u.fullName,
      "rut": _rutPayload(u), // ci-digit
    };
    return jsonEncode(payload);
  }

  String? _absolutePhoto(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final base = api.dio().options.baseUrl;
    final apiUri = Uri.parse(base);
    final origin = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
    );

    var path = raw;
    if (path.startsWith('/')) path = path.substring(1);
    if (!path.startsWith('storage/')) {
      path = 'storage/$path';
    }

    return origin.replace(path: '/$path').toString();
  }

  // Limpia todo excepto dígitos y 'K/k'
  String _cleanRutBody(String? s) {
    if (s == null) return '';
    final only = s.replaceAll(RegExp(r'[^0-9kK]'), '');
    return only.toUpperCase();
  }

  // Devuelve '12345678-9' a partir de body+dv (sin puntos)
  String _rutPayload(UserProfile u) {
    final combined = (u.rut).toString(); // por si tu modelo ya trae "ci-digit"
    if (combined.contains('-')) {
      final parts = combined.split('-');
      final body = _cleanRutBody(parts[0]);
      final dv = _cleanRutBody(parts.length > 1 ? parts[1] : '');
      if (body.isNotEmpty && dv.isNotEmpty) return '$body-$dv';
    }

    final body = _cleanRutBody(u.ci);
    final dv = _cleanRutBody(u.digit);
    if (body.isNotEmpty && dv.isNotEmpty) return '$body-$dv';

    return combined.isNotEmpty ? combined : '';
  }

  // Formatea a '12.345.678-9' para UI
  String _formatRutForUi(UserProfile u) {
    final payload = _rutPayload(u); // '12345678-9'
    if (!payload.contains('-')) return payload;

    final parts = payload.split('-');
    var body = parts[0];
    final dv = parts[1];

    final buf = StringBuffer();
    int count = 0;
    for (int i = body.length - 1; i >= 0; i--) {
      buf.write(body[i]);
      count++;
      if (count == 3 && i != 0) {
        buf.write('.');
        count = 0;
      }
    }
    final withDotsReversed = buf.toString();
    final withDots = withDotsReversed.split('').reversed.join('');

    return '$withDots-$dv';
  }

  Future<void> _logout() async {
    try {
      await context.read<Auth>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      body: FutureBuilder<UserProfile>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No pudimos cargar tu perfil.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            );
          }

          final user = snap.data!;
          return CustomScrollView(
            slivers: [
              // Header estilo DriverMainScreen (imagen + overlay + avatar + pills + salir)
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    Container(
                      height: 240,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/images/van_login.png', // mismo fondo que Driver
                              fit: BoxFit.cover,
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF0A87C3).withOpacity(.65),
                                    Colors.black.withOpacity(.35),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Avatar
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              child: CircleAvatar(
                                radius: 38,
                                backgroundColor: Colors.white.withOpacity(.15),
                                backgroundImage: (_absolutePhoto(user.photoUrl) != null)
                                    ? NetworkImage(_absolutePhoto(user.photoUrl)!)
                                    : null,
                                child: (_absolutePhoto(user.photoUrl) == null)
                                    ? const Icon(Icons.person_rounded, color: Colors.white, size: 38)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Nombre + pills (Rol + RUT)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.fullName.isNotEmpty
                                        ? 'Hola, ${user.fullName.split(' ').first}'
                                        : 'Hola, Pasajero',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                      color: Colors.white,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      const _HeaderPill(
                                        icon: Icons.badge_rounded,
                                        label: 'Rol: Pasajero',
                                      ),
                                      _HeaderPill(
                                        icon: Icons.credit_card_rounded,
                                        label: 'RUT: ${_formatRutForUi(user)}',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Botón salir (píldora)
                            SizedBox(
                              height: 40,
                              child: OutlinedButton.icon(
                                onPressed: _logout,
                                icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.white),
                                label: const Text('Salir', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white70),
                                  shape: const StadiumBorder(),
                                  backgroundColor: Colors.white.withOpacity(.12),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Contenido principal
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Tarjeta principal con QR
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Título
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Mi código de pasajero',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // QR
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: QrImageView(
                                  data: _buildQrPayload(user),
                                  version: QrVersions.auto,
                                  size: 220,
                                  gapless: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Datos
                            Text(
                              '${user.fullName} ',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'RUT: ${_formatRutForUi(user)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 18),
                            // Botones
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _refresh,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Actualizar'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Nota
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Muestra este código al conductor para registrar tu viaje. '
                              'El QR contiene tu nombre, apellido y RUT.',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
