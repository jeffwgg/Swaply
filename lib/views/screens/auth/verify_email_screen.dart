import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main_shell.dart';
import 'profile_setup_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;

  const VerifyEmailScreen({
    super.key,
    required this.email,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool isResending = false;
  bool hasResent = false;
  int resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    print("✅ VerifyEmailScreen initialized for: ${widget.email}");
    _setupAuthListener();
  }

  /// 📧 Listen for email verification changes
  void _setupAuthListener() {
    SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      final user = session?.user;

      if (user != null && user.emailConfirmedAt != null) {
        print("✅ Email verified! User: ${user.email}");

        if (!mounted) return;

        // 🔄 Refresh session to ensure latest state
        try {
          await SupabaseService.client.auth.refreshSession();
          print("✅ Session refreshed");
        } catch (e) {
          print("⚠️ Session refresh error: $e");
        }

        // 📝 Check if user has a profile
        _checkProfileAndNavigate(user.id);
      }
    });
  }

  /// 📋 Check profile existence and navigate accordingly
  Future<void> _checkProfileAndNavigate(String userId) async {
    try {
      if (!mounted) return;

      print("🔍 Checking profile for user: $userId");

      final profileResponse = await SupabaseService.client
          .from('users')
          .select()
          .eq('auth_user_id', userId)
          .maybeSingle();

      if (!mounted) return;

      if (profileResponse == null) {
        // ❌ No profile exists → Navigate to ProfileSetupScreen
        print("📝 No profile found. Navigating to ProfileSetupScreen...");
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
          (route) => false,
        );
      } else {
        // ✅ Profile exists → Navigate to MainShell
        print("✅ Profile found. Navigating to MainShell...");
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainShell(isDarkMode: false, onThemeChanged: (_) {}),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      print("❌ Error checking profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (isResending) return;

    setState(() => isResending = true);

    try {
      print("📧 Resending verification email to: ${widget.email}");
      await SupabaseService.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );

      if (!mounted) return;

      setState(() {
        hasResent = true;
        resendCountdown = 60; // 60 seconds cooldown
        isResending = false;
      });

      // Countdown timer (fixed)
      _startCountdown();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Verification email resent! Check your inbox."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      print("✅ Email resent successfully!");
    } catch (e) {
      print("❌ Resend error: $e");

      if (mounted) {
        String errorMsg = "Failed to resend. Please try again.";

        if (e.toString().contains("rate")) {
          errorMsg = "Too many attempts. Please wait before trying again.";
        } else if (e.toString().contains("connection")) {
          errorMsg = "Network error. Check your connection.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ $errorMsg"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isResending = false);
      }
    }
  }

  /// ⏱️ Start countdown timer
  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && resendCountdown > 0) {
        setState(() => resendCountdown--);
        _startCountdown();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 📧 Icon
                Container(
                  height: 120,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mail_outline,
                    size: 60,
                    color: Colors.purple,
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                Text(
                  "Verify Your Email",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Message
                Text(
                  "We've sent a verification link to:",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Email display (highlighted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.email, color: Colors.purple, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.email,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.purple,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Steps
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      _buildStep(1, "Check your inbox and spam folder"),
                      const SizedBox(height: 12),
                      _buildStep(2, "Click the verification link in the email"),
                      const SizedBox(height: 12),
                      _buildStep(3, "Complete your profile setup"),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Resend button
                GestureDetector(
                  onTap: (isResending || resendCountdown > 0) ? null : _resendVerificationEmail,
                  child: Container(
                    height: 56,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: (isResending || resendCountdown > 0)
                            ? [Colors.grey, Colors.grey]
                            : [const Color(0xFF7B61FF), const Color(0xFF5A3FFF)],
                      ),
                    ),
                    child: Center(
                      child: isResending
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              resendCountdown > 0
                                  ? "Resend in ${resendCountdown}s"
                                  : hasResent
                                      ? "Resend Email"
                                      : "Didn't receive email? Resend",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Info text
                Text.rich(
                  TextSpan(
                    text: "After clicking the link, ",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                    children: [
                      TextSpan(
                        text: "the app will automatically update",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Tips section (optional)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Check your spam/promotional folder if you don't see the email",
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Row(
      children: [
        Container(
          height: 32,
          width: 32,
          decoration: const BoxDecoration(
            color: Colors.purple,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              "$number",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
