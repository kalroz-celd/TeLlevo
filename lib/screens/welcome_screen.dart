import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/screens/driver_main_screen.dart';
import 'package:tellevo/services/auth.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isLoading = false;

  // Guards
  bool _sheetOpen = false; // evita abrir 2 bottom sheets
  bool _isPicking = false; // evita abrir 2 veces la galería/cámara

  // Debounce del tap en el avatar
  DateTime? _lastTap;
  final Duration _tapGap = const Duration(milliseconds: 450);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headerB = Color.lerp(AppColors.primary, Colors.black, 0.22)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: [
                      // Header degradado con Hero del logo
                      Container(
                        height: 260,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, headerB],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Center(
                            child: Hero(
                              tag: 'tellevo-logo',
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/images/logo.png',
                                    width: 88,
                                    height: 88,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Tellevo',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Tarjeta flotante
                      Transform.translate(
                        offset: const Offset(0, -40),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Card(
                                elevation: 0,
                                color: scheme.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: scheme.outline.withOpacity(.35),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    20,
                                    18,
                                    22,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '¡Bienvenido!',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Agrega una foto de perfil para continuar',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 18),

                                      // Selector de imagen (InkWell + debounce)
                                      Center(
                                        child: Material(
                                          color: Colors.transparent,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () async {
                                              final now = DateTime.now();
                                              if (_lastTap != null &&
                                                  now.difference(_lastTap!) <
                                                      _tapGap)
                                                return;
                                              _lastTap = now;

                                              if (_sheetOpen || _isPicking)
                                                return;
                                              await _showImagePickerOptions();
                                            },
                                            child: CircleAvatar(
                                              radius: 64,
                                              backgroundColor: scheme
                                                  .surfaceVariant
                                                  .withOpacity(.28),
                                              child:
                                                  _selectedImage == null
                                                      ? const Icon(
                                                        Icons
                                                            .add_a_photo_rounded,
                                                        size: 40,
                                                      )
                                                      : ClipOval(
                                                        child: Image.file(
                                                          _selectedImage!,
                                                          width:
                                                              128, // 2 * radius
                                                          height: 128,
                                                          fit:
                                                              BoxFit
                                                                  .cover, // ✅ rellena el círculo recortando
                                                        ),
                                                      ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (_selectedImage == null)
                                        Text(
                                          'Toca para agregar foto',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),

                                      const SizedBox(height: 24),

                                      // Botón continuar
                                      SizedBox(
                                        height: 52,
                                        child: FilledButton(
                                          onPressed:
                                              (_selectedImage == null ||
                                                      _isLoading)
                                                  ? null
                                                  : _uploadAndContinue,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          child:
                                              _isLoading
                                                  ? const SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2.6,
                                                        ),
                                                  )
                                                  : const Text(
                                                    'Continuar',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
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
                    ],
                  ),
                ),
              ),

              // Overlay de carga global (solo al subir)
              if (_isLoading) Container(color: Colors.black26),
            ],
          );
        },
      ),
    );
  }

  // ---------- BottomSheet: devuelve ImageSource y disparamos picker UNA sola vez ----------
  Future<void> _showImagePickerOptions() async {
    if (_sheetOpen) return;
    _sheetOpen = true;

    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder:
            (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt_rounded),
                    title: const Text('Tomar foto'),
                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_rounded),
                    title: const Text('Elegir de galería'),
                    onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                  ),
                ],
              ),
            ),
      );

      if (source == null) return; // cancelado

      // 👇 Parche crítico: espera a que el sheet termine de cerrarse del todo
      await Future.delayed(const Duration(milliseconds: 140));

      await _pickImage(source); // se llama exactamente una vez
    } finally {
      _sheetOpen = false;
    }
  }

  // Para GALERÍA ya no pedimos permisos manualmente (deja que image_picker los gestione)
  // Android 13+ usa Photo Picker (sin permiso). iOS pedirá el permiso cuando corresponda.

  // ---------- Selección de imagen (con guard interno definitivo) ----------
  Future<void> _pickImage(ImageSource source) async {
    if (_isPicking) return;
    _isPicking = true;

    try {
      final picked = await _picker.pickImage(source: source);

      if (picked != null && mounted) {
        setState(() => _selectedImage = File(picked.path));
      }
    } catch (e) {
      _showSnack(
        'No se pudo abrir ${source == ImageSource.camera ? "la cámara" : "la galería"}: $e',
      );
    } finally {
      _isPicking = false;
    }
  }

  // ---------- Subir y continuar ----------
  Future<void> _uploadAndContinue() async {
    if (_selectedImage == null) return;

    setState(() => _isLoading = true);
    try {
      final auth = context.read<Auth>();
      final success = await auth.uploadProfileImage(_selectedImage!);

      if (!mounted) return;
      if (success) {
        // 🔄 Refresca datos del usuario (incluyendo la nueva URL del avatar)
        await auth.reloadMe(); // <-- agrega este método en Auth (abajo)

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DriverMainScreen()),
        );
      } else {
        _showSnack('Error al subir la foto');
      }
    } catch (e) {
      if (mounted) _showSnack('Error al subir la foto: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
