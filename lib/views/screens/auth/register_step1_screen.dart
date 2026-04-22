import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import 'verify_email_screen.dart';

class RegisterStep1Screen extends StatefulWidget {
  const RegisterStep1Screen({super.key});

  @override
  State<RegisterStep1Screen> createState() => _RegisterStep1ScreenState();
}

class _RegisterStep1ScreenState extends State<RegisterStep1Screen> {

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _register() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    // 基础验证
    if (email.isEmpty || !email.contains("@")) {
      _showError("Please enter a valid email address");
      return;
    }
    if (password.length < 6) {
      _showError("Password must be at least 6 characters");
      return;
    }

    setState(() => isLoading = true);

    try {
      // 执行注册
      final response = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'swaply://login-callback',
      );

      if (response.user != null) {
        if (!mounted) return;

        print("✅ User registered: ${response.user!.id}");
        print("✅ User email: ${response.user!.email}");
        print("✅ Email confirmed at: ${response.user!.emailConfirmedAt}");

        // 🎉 Registration successful!
        // Redirect to VerifyEmailScreen (NOT back to login or MainShell)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(email: response.user!.email!),
          ),
        );
      }
    } catch (e) {
      print("❌ REGISTER ERROR: $e");
      String errorMsg = "Registration failed. Please try again.";

      // 具体的错误提示
      if (e.toString().contains("User already registered")) {
        errorMsg = "This email is already registered. Please log in instead.";
      } else if (e.toString().contains("Password")) {
        errorMsg = "Password must be at least 6 characters.";
      } else if (e.toString().contains("email")) {
        errorMsg = "Invalid email address.";
      }

      _showError(errorMsg);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [

              const SizedBox(height: 10),

              // 🔙 Back
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new),
                ),
              ),

              const SizedBox(height: 20),

              // 🧠 TITLE
              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                "Enter your email and password to get started",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 30),

              // 📦 CARD CONTAINER
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  children: [

                    // 📧 EMAIL
                    _InputField(
                      icon: Icons.email_outlined,
                      hint: "Enter your email",
                      controller: emailController,
                    ),

                    const SizedBox(height: 16),

                    // 🔒 PASSWORD
                    _InputField(
                      icon: Icons.lock_outline,
                      hint: "Enter your password",
                      isPassword: true,
                      controller: passwordController,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 🔥 BUTTON
              GestureDetector(
                onTap: isLoading ? null : _register,
                child: Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: isLoading
                          ? [Colors.grey, Colors.grey]
                          : [const Color(0xFF7B61FF), const Color(0xFF5A3FFF)],
                    ),
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
                      "Create Account",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 🔗 LOGIN
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text.rich(
                  TextSpan(
                    text: "Already have an account? ",
                    style: TextStyle(color: Colors.grey),
                    children: [
                      TextSpan(
                        text: "Log In",
                        style: TextStyle(color: Colors.purple),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatefulWidget {
  final IconData icon;
  final String hint;
  final bool isPassword;
  final TextEditingController controller;

  const _InputField({
    required this.icon,
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
        prefixIcon: Icon(widget.icon),
        hintText: widget.hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),

        // 👁 show/hide password
        suffixIcon: widget.isPassword
            ? IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
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