import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/screens/home_screen.dart';
import 'package:tellevo/screens/login_screen.dart';
import 'package:tellevo/screens/splash_screen.dart';
import 'package:tellevo/services/auth.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final auth = Auth();
  await auth.restoreSession();
  debugPrint(
    'Auth.restoreSession → isLoggedIn=${auth.isLoggedIn}, user.id=${auth.user.id}, token=${auth.token}',
  );

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: auth)],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tellevo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      home: const SplashScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
      },
    );
  }
}
