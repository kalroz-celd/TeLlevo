import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/services/auth.dart';

/// Ruta con transición fade
Route _fadeRoute(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Future<void> _decideNext() async {

    /// 🔹 Opción A: si tu Auth expone un método async para restaurar sesión:
    /// final isLoggedIn = await auth.restoreSession(); // <- implementa en tu Auth
    ///
    /// 🔹 Opción B: si tu Auth tiene un getter/bool directo:
    /// final isLoggedIn = auth.isLoggedIn; // <- ajusta a tu API real

    final isLoggedIn = await context.read<Auth>().restoreSession();
Navigator.of(context).pushReplacementNamed(isLoggedIn ? '/home' : '/login');

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(isLoggedIn ? '/home' : '/login');
  }

  @override
  void initState() {
    super.initState();
    // Pequeña pausa para ver la animación y luego decidir
    Future.delayed(const Duration(milliseconds: 1200), _decideNext);
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    final secondary = Color.lerp(AppColors.primary, Colors.black, 0.25)!;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primary, secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .85, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(scale: value, child: child),
            ),
            child: const _LogoHero(),
          ),
        ),
      ),
    );
  }
}

/// Hero del logo reutilizable entre Splash y Login
class _LogoHero extends StatelessWidget {
  const _LogoHero();

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'tellevo-logo',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/logo.png', // PNG 512x512 con transparencia
            width: 140,
            height: 140,
          ),
          const SizedBox(height: 12),
          const Text(
            'Tellevo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
