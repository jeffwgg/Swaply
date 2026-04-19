  import 'package:flutter/material.dart';
  import 'services/supabase_service.dart';
  import 'views/screens/main_shell.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import 'views/screens/auth/profile_setup_screen.dart';

  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SupabaseService.initialize();
    runApp(const MyApp());
  }

  class MyApp extends StatefulWidget {
    const MyApp({super.key});

    @override
    State<MyApp> createState() => _MyAppState();
  }

  class _MyAppState extends State<MyApp> {
    @override
    Widget build(BuildContext context) {
      return MaterialApp(
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

          final session = snapshot.data?.session;
          final user = session?.user ?? SupabaseService.client.auth.currentUser;

          if (user == null) {
            print("👤 User is null - Guest mode");
            return const MainShell();
          }

          if (user.emailConfirmedAt == null) {
            print("⏳ Email not confirmed yet for ${user.email}");
            return const MainShell();
          }

          print("✅ Email confirmed for ${user.email}. Checking profile...");
          return FutureBuilder(
            future: SupabaseService.client
                .from('users')
                .select()
                .eq('auth_user_id', user.id)
                .maybeSingle(),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              if (profileSnapshot.hasError) {
                print("❌ Profile query error: ${profileSnapshot.error}");
                return const MainShell();
              }

              final profile = profileSnapshot.data;

              if (profile == null) {
                print("📝 No profile found for user. Showing ProfileSetupScreen.");
                return const ProfileSetupScreen();
              }

              return const MainShell();
            },
          );
        },
      );
    }
  }
