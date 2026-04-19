import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/views/screens/profile/profile_tabs.dart';
import '/services/supabase_service.dart';
import '../auth/login_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const ProfileScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 🟢 关键判断：获取当前用户状态
    final user = SupabaseService.client.auth.currentUser;
    print("🔥 NEW PROFILE SCREEN RUNNING");
    // 💡 如果没登录，显示游客引导界面 (Guest View)
    if (user == null) {
      return _buildGuestView(context);
    }

    // ⏳ 如果已登录但邮件未验证，显示验证提示
    if (user.emailConfirmedAt == null) {
      return _buildUnverifiedEmailView(context, user);
    }

    // ✅ 如果已登录且邮件已验证，显示完整的 Profile UI
    return _buildFullProfileView(context);
  }

  // --- 1. 游客界面 (Guest View) ---
  Widget _buildGuestView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline, size: 60, color: Colors.purple),
              ),
              const SizedBox(height: 24),
              const Text(
                "Welcome to Swaply",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Log in to see your profile, manage listings, and start swapping!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Container(
                  height: 50,
                  width: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B61FF), Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      "Login / Register",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 1.5. 邮件未验证界面 (Unverified Email View) ---
  Widget _buildUnverifiedEmailView(BuildContext context, User user) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mail_outline, size: 60, color: Colors.orange),
              ),
              const SizedBox(height: 24),
              const Text(
                "Verify Your Email",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "A verification link has been sent to ${user.email}.\n\nPlease check your email and click the link to verify your account.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () async {
                  // 重新发送验证邮件
                  try {
                    await SupabaseService.client.auth.resend(
                      type: OtpType.signup,
                      email: user.email!,
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Verification email resent! Check your inbox."),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Error: ${e.toString()}")),
                      );
                    }
                  }
                },
                child: Container(
                  height: 50,
                  width: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B61FF), Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      "Resend Email",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullProfileView(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;

    return FutureBuilder(
      future: SupabaseService.client
          .from('users')
          .select()
          .eq('auth_user_id', user!.id)
          .maybeSingle(),
      builder: (context, snapshot) {
        // ⏳ Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ❌ Error
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text("Failed to load profile"),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Go Back"),
                  ),
                ],
              ),
            ),
          );
        }

        final profile = snapshot.data as Map<String, dynamic>?;

        if (profile == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline, size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("Profile not found"),
                ],
              ),
            ),
          );
        }

        // ✅ Data loaded successfully
        final fullName = profile['full_name'] ?? 'User';
        final username = profile['username'] ?? 'user';
        final bio = profile['bio'] ?? 'No bio yet';
        final email = profile['email'] ?? '';
        final phone = profile['phone'] ?? '';

        return Scaffold(
          backgroundColor: const Color(0xFFF4F3F8),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 🔝 TOP BAR
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.arrow_back_ios_new),
                        ),
                        Text(
                          fullName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SettingsScreen(
                                  isDarkMode: isDarkMode,
                                  onThemeChanged: onThemeChanged,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 👤 PROFILE SECTION
                  Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.grey[300],
                            child: Icon(
                              Icons.person,
                              size: 45,
                              color: Colors.grey[600],
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.purple,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fullName,
                        style:
                            const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "@$username",
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      // 🔥 EDIT BUTTON
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        height: 45,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7B61FF), Color(0xFF5A3FFF)],
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            "Edit Profile",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 📊 STATS CARD
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.purple.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        _Stat("0", "SOLD"),
                        _Divider(),
                        _Stat("0", "TRADES"),
                        _Divider(),
                        _Stat("0d", "JOINED"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ℹ️ INFO SECTION
                  // Container(
                  //   margin: const EdgeInsets.symmetric(horizontal: 16),
                  //   padding: const EdgeInsets.all(16),
                  //   decoration: BoxDecoration(
                  //     color: Colors.white,
                  //     borderRadius: BorderRadius.circular(16),
                  //     border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  //   ),
                  //   child: Column(
                  //     crossAxisAlignment: CrossAxisAlignment.start,
                  //     children: [
                  //       const Text(
                  //         "Contact Information",
                  //         style: TextStyle(fontWeight: FontWeight.bold),
                  //       ),
                  //       const SizedBox(height: 12),
                  //       _buildInfoRow(Icons.email, "Email", email),
                  //       const SizedBox(height: 12),
                  //       _buildInfoRow(Icons.phone, "Phone", phone.isEmpty ? "Not set" : phone),
                  //     ],
                  //   ),
                  // ),

                  const SizedBox(height: 20),

                  //tabs
                  SizedBox(height: 400, child: ProfileTabs(userId: 8)), //todo

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.purple, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

// --- 以下是你所有的辅助 UI 组件 (完全保持不变) ---

class _Badge extends StatelessWidget {
  const _Badge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text("SUPER TRADER", style: TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: Colors.grey[300]);
  }
}
