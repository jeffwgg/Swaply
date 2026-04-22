import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool showCurrentPassword = false;
  bool showNewPassword = false;
  bool showConfirmPassword = false;
  bool isUpdating = false;

  @override
  void dispose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _validateInputs() {
    String currentPassword = currentPasswordController.text.trim();
    String newPassword = newPasswordController.text.trim();
    String confirmPassword = confirmPasswordController.text.trim();

    if (currentPassword.isEmpty) {
      _showError("Current password is required");
      return false;
    }

    if (newPassword.isEmpty) {
      _showError("New password is required");
      return false;
    }

    if (newPassword.length < 6) {
      _showError("New password must be at least 6 characters");
      return false;
    }

    if (confirmPassword.isEmpty) {
      _showError("Please confirm your new password");
      return false;
    }

    if (newPassword != confirmPassword) {
      _showError("Passwords do not match");
      return false;
    }

    if (currentPassword == newPassword) {
      _showError("New password must be different from current password");
      return false;
    }

    return true;
  }

  /// 🔒 Update password using Supabase
  Future<void> _updatePassword() async {
    if (!_validateInputs()) return;

    setState(() => isUpdating = true);

    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) throw Exception("User session not found");

      final currentPassword = currentPasswordController.text.trim();
      final newPassword = newPasswordController.text.trim();

      print("🔐 Updating password for user: ${user.email}");

      // Update password using Supabase auth
      await SupabaseService.client.auth.signInWithPassword(
        email: user.email!,
        password: currentPassword,
      );
      
      await SupabaseService.client.auth.updateUser(
        UserAttributes(
          password: newPassword,
        ),
      );
      if (!mounted) return;

      _showSuccess("✅ Password updated successfully!");

      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print("❌ PASSWORD UPDATE ERROR: $e");
      String errorMsg = "Error: ${e.toString()}";

      if (e.toString().contains("Invalid login credentials")) {
        errorMsg = "Current password is incorrect";
      } else if (e.toString().contains("weak password")) {
        errorMsg = "Password is too weak. Use a stronger password.";
      } else if (e.toString().contains("same password")) {
        errorMsg = "New password must be different from current password";
      }

      _showError(errorMsg);
    } finally {
      if (mounted) {
        setState(() => isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text("Change Password"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Choose a strong password with at least 6 characters",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 🔒 Current Password
              _buildSectionTitle("Current Password"),
              _PasswordField(
                controller: currentPasswordController,
                hint: "Enter your current password",
                obscure: !showCurrentPassword,
                onToggleVisibility: () {
                  setState(() => showCurrentPassword = !showCurrentPassword);
                },
              ),

              const SizedBox(height: 24),

              // 🔐 New Password
              _buildSectionTitle("New Password"),
              _PasswordField(
                controller: newPasswordController,
                hint: "Enter your new password",
                obscure: !showNewPassword,
                onToggleVisibility: () {
                  setState(() => showNewPassword = !showNewPassword);
                },
              ),

              const SizedBox(height: 24),

              // ✔️ Confirm Password
              _buildSectionTitle("Confirm New Password"),
              _PasswordField(
                controller: confirmPasswordController,
                hint: "Confirm your new password",
                obscure: !showConfirmPassword,
                onToggleVisibility: () {
                  setState(() => showConfirmPassword = !showConfirmPassword);
                },
              ),

              const SizedBox(height: 40),

              // 💾 Update Button
              GestureDetector(
                onTap: isUpdating ? null : _updatePassword,
                child: Container(
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: isUpdating
                          ? [Colors.grey, Colors.grey]
                          : [const Color(0xFF7B61FF), const Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: Center(
                    child: isUpdating
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Update Password",
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

              // Cancel Button
              GestureDetector(
                onTap: isUpdating ? null : () => Navigator.pop(context),
                child: Container(
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.purple),
                  ),
                  child: const Center(
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.purple,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Colors.black87,
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
        prefixIcon: const Icon(Icons.lock_outline),
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: onToggleVisibility,
        ),
      ),
    );
  }
}
