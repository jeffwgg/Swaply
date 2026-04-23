import 'package:flutter/material.dart';
import '../../../core/utils/app_snack_bars.dart';
import 'register_step1_screen.dart';
import '/services/supabase_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const SizedBox(height: 10),

              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close),
              ),

              const SizedBox(height: 20),

              // 🖼 Image (placeholder)
              SvgPicture.asset(
                'assets/Swaplylogin.svg',
                height: 250,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 24),

              // 👋 Title
              Center(
                child: Column(
                  children: const [
                    Text(
                      "Welcome Back",
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Log in to start trading with your community",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 📧 EMAIL
              const Text("Email"),
              const SizedBox(height: 6),

              _InputField(
                hint: "Enter your email",
                controller: emailController,
              ),

              const SizedBox(height: 16),

              // 🔒 PASSWORD + FORGOT
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Password"),
                  GestureDetector(
                    onTap: _showForgotPasswordDialog,
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(color: Colors.purple),
                    ),
                  )
                ],
              ),

              const SizedBox(height: 6),

              _InputField(
                hint: "Enter your password",
                controller: passwordController,
                isPassword: true,
              ),

              const SizedBox(height: 24),

              // 🔥 LOGIN BUTTON
              GestureDetector(
                onTap: isLoading ? null : _validateLogin,
                child: Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF5A2CA0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Center(
                    child: isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Text(
                      "Log In",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // 🔗 SIGN UP
              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterStep1Screen()),
                    );
                  },
                  child: const Text.rich(
                    TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: Colors.grey),
                      children: [
                        TextSpan(
                          text: "Sign Up",
                          style: TextStyle(color: Colors.purple),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 200),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    AppSnackBars.error(context, message);
  }

  void _showForgotPasswordDialog() {
    final forgotEmailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Reset Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enter your email address to receive a password reset link.",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: forgotEmailController,
                decoration: InputDecoration(
                  hintText: "Enter your email",
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = forgotEmailController.text.trim();
                if (email.isEmpty) {
                  _showError("Email is required");
                  return;
                }
                if (!email.contains("@")) {
                  _showError("Invalid email format");
                  return;
                }

                try {
                  await SupabaseService.client.auth
                      .resetPasswordForEmail(
                    email,
                    redirectTo: 'swaply://login-callback',
                  );
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    AppSnackBars.success(
                      context,
                      'Password reset email sent! Check your inbox.',
                    );
                  }
                } catch (e) {
                  print("Error sending reset email: $e");
                  _showError("Failed to send reset email. Please try again.");
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A2CA0),
              ),
              child: const Text(
                "Send Reset Link",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _validateLogin() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty) {
      _showError("Email is required");
      return;
    }

    if (!email.contains("@")) {
      _showError("Invalid email format");
      return;
    }

    if (password.isEmpty) {
      _showError("Password is required");
      return;
    }

    setState(() => isLoading = true);

    try {
      print("🔐 Attempting login for: $email");

      final response = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        print("✅ Login successful for ${response.user!.email}");

        // ✅ 登录成功
        if (mounted) {
          AppSnackBars.success(context, 'Login successful!');
          Navigator.pop(context);
        }
      }
    } catch (e) {
      print("❌ LOGIN ERROR: $e");

      if (mounted) {
        String error = e.toString().toLowerCase();
        String errorMsg = "Invalid email or password";

        if (error.contains("invalid login credentials")) {
          errorMsg = "Invalid email or password. Please try again.";
        } else if (error.contains("user not found")) {
          errorMsg = "No account found with this email. Please register.";
        } else if (error.contains("email not confirmed")) {
          errorMsg = "Please verify your email before logging in.";
        } else if (error.contains("account is disabled")) {
          errorMsg = "Your account has been disabled. Contact support.";
        } else if (error.contains("connection")) {
          errorMsg = "Network error. Please check your connection.";
        }

        _showError(errorMsg);
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }
}

class _InputField extends StatefulWidget {
  final String hint;
  final bool isPassword;
  final TextEditingController controller;

  const _InputField({
    required this.hint,
    required this.controller,
    this.isPassword = false,
  });

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: widget.isPassword ? obscure : false,
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        // 👁 Password visibility toggle
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() => obscure = !obscure);
                },
              )
            : null,
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String text;

  const _SocialButton(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(child: Text(text)),
    );
  }
}

