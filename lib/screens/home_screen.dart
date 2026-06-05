import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:tellevo/screens/login_screen.dart';
import 'package:tellevo/screens/role_home_resolver.dart';
import 'package:tellevo/screens/welcome_screen.dart';
import 'package:tellevo/services/auth.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    readToken();
  }

  Future<void> readToken() async {
    final token = await storage.read(key: 'token') ?? '';
    if (!mounted) return;
    context.read<Auth>().tryToken(token: token);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<Auth>(
      builder: (context, auth, _) {
        // 1) Si aún no estamos autenticados, mostramos Login
        if (!auth.authenticated) {
          return const LoginScreen();
        }
        // 2) Ya autenticados pero sin foto → Welcome para agregarla
        if (!auth.hasProfilePhoto) {
          return const WelcomeScreen();
        }
        // 3) Usuario autenticado Y tiene foto → decidir según rol
        return resolveHomeForRoles(auth.user.roles);
      },
    );
  }
}
