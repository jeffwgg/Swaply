import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import '../main_shell.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}


class _ProfileSetupScreenState extends State<ProfileSetupScreen> {

  final usernameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final fullNameController = TextEditingController();
  final bioController = TextEditingController();

  String gender = "Male";
  DateTime? selectedDate;
  bool isSaving = false;

  @override
  void dispose() {
    usernameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    fullNameController.dispose();
    bioController.dispose();
    super.dispose();
  }

  // 📅 选择日期
  void _pickDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.purple),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ✅ 保存 Profile 到数据库
  Future<void> _saveProfile() async {
    setState(() => isSaving = true);

    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) throw Exception("User session not found");

      print("📝 Saving profile for User ID: ${user.id}");
      print("📧 User Email: ${user.email}");

      // 准备要插入的数据包
      final updates = {
        'auth_user_id': user.id,
        'email': user.email,
        'username': usernameController.text.trim(),
        'full_name': fullNameController.text.trim(),
        'bio': bioController.text.trim(),
        'phone': phoneController.text.trim(),
        'gender': gender,
        'birthdate': selectedDate?.toIso8601String().split('T')[0],
        'created_at': DateTime.now().toIso8601String(),
      };

      print("📦 Inserting data: $updates");

      // 执行插入
      final response = await SupabaseService.client.from('users').insert(updates);

      print("✅ Profile saved successfully!");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile setup complete! Welcome to Swaply."),
          backgroundColor: Colors.green,
        ),
      );

      // 💡 关键：使用 pushAndRemoveUntil 清空导航栈，防止返回到注册/验证页面
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) =>  MainShell()),
        (route) => false,
      );

    } catch (e) {
      print("❌ FULL ERROR DETAIL: $e");
      print("❌ Error type: ${e.runtimeType}");

      // 具体的错误诊断
      String errorMsg = "Error: ${e.toString()}";
      if (e.toString().contains("duplicate key") || e.toString().contains("already exists")) {
        errorMsg = "Profile already exists. Please contact support.";
      } else if (e.toString().contains("permission denied")) {
        errorMsg = "Permission denied. Please check your account settings.";
      } else if (e.toString().contains("connection")) {
        errorMsg = "Network error. Please check your connection and try again.";
      }

      // 如果你想在手机屏幕上也看到具体错误
      _showError(errorMsg);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // ✅ 验证输入
  Future<void> _validateAndContinue() async {
    String fullName = fullNameController.text.trim();
    String username = usernameController.text.trim();
    String phone = phoneController.text.trim();

    // Validation checks
    if (fullName.isEmpty) {
      _showError("Full name is required");
      return;
    }

    if (fullName.length < 2) {
      _showError("Full name must be at least 2 characters");
      return;
    }

    if (username.isEmpty) {
      _showError("Username is required");
      return;
    }

    if (username.length < 3) {
      _showError("Username must be at least 3 characters");
      return;
    }

    if (username.length > 20) {
      _showError("Username must be at most 20 characters");
      return;
    }

    // Username can only contain letters, numbers, and underscores
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      _showError("Username can only contain letters, numbers, and underscores");
      return;
    }

    if (phone.isEmpty) {
      _showError("Phone number is required");
      return;
    }

    if (phone.length < 7) {
      _showError("Please enter a valid phone number");
      return;
    }

    if (selectedDate == null) {
      _showError("Please select your birthdate");
      return;
    }

    // Check if user is at least 13 years old
    final today = DateTime.now();
    final age = today.year - selectedDate!.year;
    if (age < 13) {
      _showError("You must be at least 13 years old to use Swaply");
      return;
    }

    // All validations passed, proceed to save
    await _saveProfile();
  }


  @override
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

              const Text(
                "Complete Your Profile",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              const Text(
                "Add your personal details",
                style: TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 30),

              // 👤 PROFILE IMAGE
              GestureDetector(
                onTap: () {
                  // Step 2 (later)
                },
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[300],
                      child: const Icon(Icons.person, size: 50),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.purple,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 16),
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 📦 CARD
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  children: [
                    _InputField(controller: usernameController, icon: Icons.person, hint: "Username"),
                    const SizedBox(height: 12),
                    _InputField(controller: fullNameController, icon: Icons.badge, hint: "Full Name"),
                    const SizedBox(height: 12),
                    _InputField(controller: bioController, icon: Icons.edit, hint: "Bio"),
                    const SizedBox(height: 12),
                    _InputField(controller: phoneController, icon: Icons.phone, hint: "Phone Number"),
                    const SizedBox(height: 12),
                    _InputField(controller: addressController, icon: Icons.location_on, hint: "Address"),
                    const SizedBox(height: 12),

                    // 生日选择
                    _buildDatePicker(),
                    const SizedBox(height: 16),

                    // 性别选择
                    _buildGenderPicker(),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 🔥 BUTTON
              GestureDetector(
                onTap: isSaving ? null : _validateAndContinue,
                child: Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: isSaving
                          ? [Colors.grey, Colors.grey]
                          : [const Color(0xFF7B61FF), const Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: Center(
                    child: isSaving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Text(
                      "Complete Profile",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

  // 📅 STEP 3 — DATE PICKER
  Widget _buildAvatarSection() {
    return Stack(
      children: [
        CircleAvatar(radius: 50, backgroundColor: Colors.grey[300], child: const Icon(Icons.person, size: 50)),
        Positioned(
          bottom: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle),
            child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
          ),
        )
      ],
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () => _pickDate(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(color: const Color(0xFFF7F7FB), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today),
            const SizedBox(width: 10),
            Text(selectedDate == null ? "Select Birthdate" : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderPicker() {
    return Row(
      children: [
        _GenderOption(label: "Male", selected: gender == "Male", onTap: () => setState(() => gender = "Male")),
        const SizedBox(width: 10),
        _GenderOption(label: "Female", selected: gender == "Female", onTap: () => setState(() => gender = "Female")),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hint;

  const _InputField({
    required this.controller,
    required this.icon,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F7FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenderOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.purple : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.purple,
              ),
            ),
          ),
        ),
      ),
    );
  }
}