import 'dart:async';
import 'package:flutter/material.dart';
import 'services/supabase_service.dart';
import 'views/screens/main_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'views/screens/auth/profile_setup_screen.dart';
import 'views/screens/auth/reset_password_screen.dart';
import 'package:swaply/services/local_db_service.dart';
import 'services/stripe_payment_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  await LocalDbService.instance.initialize();
  await NotificationService.instance.initialize();
  await StripePaymentService.ensureStripeConfigured();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Swaply',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D2B9F)),
      ),
      themeMode: ThemeMode.light,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseService.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = snapshot.data?.session;
        final user = session?.user ?? SupabaseService.client.auth.currentUser;
        final event = snapshot.data?.event;

        if (event == AuthChangeEvent.passwordRecovery && session != null) {
          return const ResetPasswordScreen();
        }

        if (user == null) {
          return const MainShell();
        }

        if (user.emailConfirmedAt == null) {
          return const MainShell();
        }

        return FutureBuilder(
          future: SupabaseService.client
              .from('users')
              .select()
              .eq('id', user.id)
              .maybeSingle(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (profileSnapshot.hasError) {
              return const MainShell();
            }

            final profile = profileSnapshot.data;

            if (profile == null) {
              return const ProfileSetupScreen();
            }

            return const MainShell();
          },
        );
      },
    );
  }
}
