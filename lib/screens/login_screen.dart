import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/services/auth.dart';
import 'package:tellevo/screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  String _deviceName = '';

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
  }

  Future<void> _loadDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _deviceName = androidInfo.model ?? '';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _deviceName = iosInfo.utsname.machine ?? '';
      }
    } catch (e) {
      debugPrint('Error leyendo device info: $e');
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    if (_deviceName.isEmpty) {
      await _loadDeviceName();
    }

    final creds = {
      'rut': _usernameController.text.trim(),
      'password': _passwordController.text,
      'device_name': _deviceName,
    };

    setState(() => _loading = true);
    final auth = Provider.of<Auth>(context, listen: false);

    try {
      final success = await auth.login(creds: creds);
      if (!mounted) return;

      if (success) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al iniciar sesión')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Stack(
                children: [
                  // HEADER con imagen de fondo (van.png)
                  Container(
                    height: 300,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(28),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Imagen de la van
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                          child: Image.asset(
                            'assets/images/van_login.png', // 👈 tu imagen en .png
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Overlay oscuro para contraste
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(28),
                            ),
                            color: Colors.black.withOpacity(0.35),
                          ),
                        ),
                        // Logo centrado
                        Align(
                          alignment: Alignment.center,
                          child: Hero(
                            tag: 'tellevo-logo',
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 160,
                              height: 160,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tarjeta flotante del formulario
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 250, 16, 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Card(
                            elevation: 6,
                            color: scheme.surface.withOpacity(0.95),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: scheme.outline.withOpacity(.25)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Iniciar sesión',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Accede para continuar tu viaje',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 18),

                                    // Usuario
                                    TextFormField(
                                      controller: _usernameController,
                                      decoration: InputDecoration(
                                        labelText: 'RUT',
                                        prefixIcon: const Icon(Icons.person_outline_rounded),
                                        filled: true,
                                        fillColor: scheme.surfaceVariant.withOpacity(.28),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Ingresa tu RUT';
                                        final clean = v.toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
                                        if (clean.length < 2) return 'RUT inválido';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),

                                    // Contraseña
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      decoration: InputDecoration(
                                        labelText: 'Contraseña',
                                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                                        filled: true,
                                        fillColor: scheme.surfaceVariant.withOpacity(.28),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_rounded
                                                : Icons.visibility_off_rounded,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword = !_obscurePassword;
                                            });
                                          },
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Por favor ingrese su contraseña';
                                        }
                                        if (value.length < 4) {
                                          return 'La contraseña debe tener al menos 4 caracteres';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),

                                    // Botón
                                    SizedBox(
                                      height: 48,
                                      child: FilledButton(
                                        onPressed: _loading ? null : _login,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: _loading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(strokeWidth: 2.6),
                                              )
                                            : const Text('Iniciar Sesión'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
