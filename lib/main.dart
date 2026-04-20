  import 'package:flutter/material.dart';
  import 'services/supabase_service.dart';
  import 'views/screens/main_shell.dart';
  import 'services/stripe_payment_service.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import 'views/screens/auth/profile_setup_screen.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SupabaseService.initialize();
    const stripeKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
    const intentUrl = String.fromEnvironment('STRIPE_PAYMENT_INTENT_URL');

    try {
      await StripePaymentService.ensureStripeConfigured();
      print("✅ Stripe 初始配置成功");
    } catch (e) {
      print("❌ Stripe 初始配置失败: $e");
    }
    // 2. Print them to the debug console
    print('--- Debugging Environment Variables ---');
    print('Stripe Key: ${stripeKey.isEmpty ? "NOT FOUND ❌" : "FOUND ✅"}');
    print('Intent URL: $intentUrl');
    print('---------------------------------------');
    runApp(const MyApp());
  }

  class MyApp extends StatefulWidget {
    const MyApp({super.key});

    @override
    State<MyApp> createState() => _MyAppState();
  }

  class _MyAppState extends State<MyApp> {
    bool isDarkMode = false;

    @override
    void initState() {
      super.initState();
      _loadThemePreference();
    }

    /// 📱 Load theme preference from SharedPreferences
    Future<void> _loadThemePreference() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          isDarkMode = prefs.getBool('isDarkMode') ?? false;
        });
        print("✅ Theme preference loaded: isDarkMode = $isDarkMode");
      } catch (e) {
        print("⚠️ Error loading theme preference: $e");
      }
    }

    /// 💾 Save theme preference to SharedPreferences
    Future<void> _saveThemePreference(bool value) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isDarkMode', value);
        print("✅ Theme preference saved: isDarkMode = $value");
      } catch (e) {
        print("❌ Error saving theme preference: $e");
      }
    }

    void toggleTheme(bool value) async {
      setState(() => isDarkMode = value);
      await _saveThemePreference(value);
    }

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: 'Swaply',
        debugShowCheckedModeBanner: false,

        theme: ThemeData(
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D2B9F)),
        ),

        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),

        themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,

        home: AuthGate(
          isDarkMode: isDarkMode,
          onThemeChanged: toggleTheme,
        ),
      );
    }
  }

  class AuthGate extends StatelessWidget {
    final bool isDarkMode;
    final Function(bool) onThemeChanged;

    const AuthGate({
      super.key,
      required this.isDarkMode,
      required this.onThemeChanged,
    });

    @override
    Widget build(BuildContext context) {
      // 使用 StreamBuilder 监听登录状态变化，但不再根据 user == null 返回不同的 Page
      // 这样当用户在 Profile 页面点击登录成功后，Stream 会触发 UI 自动刷新
      return StreamBuilder<AuthState>(
        stream: SupabaseService.client.auth.onAuthStateChange,
        builder: (context, snapshot) {

          final session = snapshot.data?.session;
          final user = session?.user ?? SupabaseService.client.auth.currentUser;

          // ❌ 用户未登录：显示带身份验证守卫的 MainShell（Guest 模式在 ProfileScreen 处理）
          if (user == null) {
            print("👤 User is null - Guest mode");
            return MainShell(isDarkMode: isDarkMode, onThemeChanged: onThemeChanged);
          }

          // ⏳ 用户已登录但邮件未验证
          if (user.emailConfirmedAt == null) {
            print("⏳ Email not confirmed yet for ${user.email}");
            // 用户可以游览应用，但 Profile 页面会提示验证邮件
            return MainShell(isDarkMode: isDarkMode, onThemeChanged: onThemeChanged);
          }

          // ✅ 用户已登录且邮件已验证：检查是否有 profile
          print("✅ Email confirmed for ${user.email}. Checking profile...");
          return FutureBuilder(
            // users.id maps directly to auth.users.id (UUID)
            future: SupabaseService.client
                .from('users')
                .select()
              .eq('id', user.id)
                .maybeSingle(),
            builder: (context, profileSnapshot) {
              // ⏳ 加载中，显示一个菊花图，防止白屏
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              // ❌ 查询出错
              if (profileSnapshot.hasError) {
                print("❌ Profile query error: ${profileSnapshot.error}");
                // 即使查询失败，也让用户进入应用，Profile 页面会显示错误
                return MainShell(isDarkMode: isDarkMode, onThemeChanged: onThemeChanged);
              }

              final profile = profileSnapshot.data;

              // ❌ 没有 profile：显示 ProfileSetupScreen
              if (profile == null) {
                print("📝 No profile found for user. Showing ProfileSetupScreen.");
                return const ProfileSetupScreen();
              }

              // ✅ 有 profile 了，正式进入 App
              return MainShell(
                isDarkMode: isDarkMode,
                onThemeChanged: onThemeChanged,
              );
            },
          );
        },
      );
    }
  }

