import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool showNewPassword = false;
  bool showConfirmPassword = false;
  bool isSubmitting = false;

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  bool _validate() {
    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (newPassword.isEmpty) {
      _showMessage('Please enter a new password.');
      return false;
    }

    if (newPassword.length < 6) {
      _showMessage('New password must be at least 6 characters.');
      return false;
    }

    if (confirmPassword.isEmpty) {
      _showMessage('Please confirm your new password.');
      return false;
    }

    if (newPassword != confirmPassword) {
      _showMessage('Passwords do not match.');
      return false;
    }

    return true;
  }

  Future<void> _submitNewPassword() async {
    if (!_validate()) return;

    setState(() => isSubmitting = true);

    try {
      final newPassword = newPasswordController.text.trim();
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;

      _showMessage('Password updated successfully!', color: Colors.green);

      // ✅ Wait a moment for auth state to update
      await Future.delayed(const Duration(milliseconds: 1500));
      
      if (!mounted) return;

      // ✅ Let the AuthGate handle the navigation naturally
      // The auth state should now be updated and show the appropriate screen
      // If we're still on ResetPasswordScreen, pop back
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Reset password error: $e');
      var errorMsg = 'Failed to update password. Please try again.';
      if (e.toString().toLowerCase().contains('weak password')) {
        errorMsg = 'Password is too weak. Use a stronger password.';
      } else if (e.toString().toLowerCase().contains('expired') ||
          e.toString().toLowerCase().contains('token')) {
        errorMsg = 'The recovery link has expired. Request a new one.';
      }
      _showMessage(errorMsg);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text(
          'Reset Password',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFF4F3F8),
        elevation: 0,
        foregroundColor: Colors.black,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios_new),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Set a new password for your account.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              const Text(
                'New Password',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              _PasswordField(
                controller: newPasswordController,
                hint: 'Enter your new password',
                obscure: !showNewPassword,
                onToggleVisibility: () {
                  setState(() => showNewPassword = !showNewPassword);
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Confirm Password',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              _PasswordField(
                controller: confirmPasswordController,
                hint: 'Confirm your password',
                obscure: !showConfirmPassword,
                onToggleVisibility: () {
                  setState(() => showConfirmPassword = !showConfirmPassword);
                },
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: isSubmitting ? null : _submitNewPassword,
                child: Container(
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: isSubmitting
                          ? [Colors.grey, Colors.grey]
                          : [const Color(0xFF7B61FF), const Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: Center(
                    child: isSubmitting
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Update Password',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: isSubmitting ? null : () => Navigator.pop(context),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.purple[700],
                      fontWeight: FontWeight.bold,
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
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggleVisibility;

  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FB),
        suffixIcon: GestureDetector(
          onTap: onToggleVisibility,
          child: Icon(obscure ? Icons.visibility_off : Icons.visibility),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
