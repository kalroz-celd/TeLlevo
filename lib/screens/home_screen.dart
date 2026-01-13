import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:tellevo/screens/login_screen.dart';
import 'package:tellevo/screens/driver_main_screen.dart';
import 'package:tellevo/screens/passenger_main_screen.dart';
import 'package:tellevo/screens/welcome_screen.dart';
import 'package:tellevo/services/auth.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  final storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    readToken();
  }

  void readToken() async{
    String token = await storage.read(key: 'token') ?? '';
    Provider.of<Auth>(context, listen: false).tryToken(token: token);
  }

  void _logout() {
      Provider.of<Auth>(context, listen: false).logout();
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
        final userRoles = auth.user.roles;
        if (userRoles.contains('superAdmin') || userRoles.contains('admin') || userRoles.contains('driver')) {
          return const DriverMainScreen();
        } else if (userRoles.contains('passenger')) {
          return const PassengerMainScreen();
        } else {
          // Rol desconocido
          return Scaffold(
            body: Center(child: Text('Rol no autorizado')),
          );
        }
      },
    );
  }
}