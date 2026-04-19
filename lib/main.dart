import 'package:flutter/material.dart';
import 'core/constants/app_config.dart';
import 'services/stripe_payment_service.dart';
import 'services/supabase_service.dart';
import 'views/screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  if (AppConfig.hasStripePublishableKey) {
    await StripePaymentService.ensureStripeConfigured();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swaply',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D2B9F)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MainShell(),
    );
  }
}
