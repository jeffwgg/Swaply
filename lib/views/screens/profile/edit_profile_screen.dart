import 'package:flutter/material.dart';
import '/services/supabase_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final fullNameController = TextEditingController();
  final usernameController = TextEditingController();
  final bioController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController(); // Read-only

  String gender = "Male";
  DateTime? selectedDate;
  bool isSaving = false;
  bool isLoading = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    fullNameController.dispose();
    usernameController.dispose();
    bioController.dispose();
    phoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

  /// 📋 Load current user profile
  Future<void> _loadUserProfile() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) throw Exception("User session not found");

      print("📝 Loading profile for User ID: ${user.id}");

      final profileResponse = await SupabaseService.client
          .from('users')
          .select()
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (profileResponse == null) {
        throw Exception("Profile not found");
      }

      // Pre-fill all fields
      setState(() {
        fullNameController.text = profileResponse['full_name'] ?? '';
        usernameController.text = profileResponse['username'] ?? '';
        bioController.text = profileResponse['bio'] ?? '';
        phoneController.text = profileResponse['phone'] ?? '';
        emailController.text = profileResponse['email'] ?? '';
        gender = profileResponse['gender'] ?? 'Male';

        if (profileResponse['birthdate'] != null) {
          selectedDate = DateTime.parse(profileResponse['birthdate']);
        }

        isLoading = false;
      });

      print("✅ Profile loaded successfully");
    } catch (e) {
      print("❌ Error loading profile: $e");
      if (mounted) {
        setState(() {
          loadError = "Error: $e";
          isLoading = false;
        });
      }
    }
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

  /// 📅 Pick date
  void _pickDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime(2000),
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

  /// ✅ Validate input before saving
  bool _validateInput() {
    String fullName = fullNameController.text.trim();
    String username = usernameController.text.trim();
    String phone = phoneController.text.trim();

    if (fullName.isEmpty) {
      _showError("Full name is required");
      return false;
    }

    if (fullName.length < 2) {
      _showError("Full name must be at least 2 characters");
      return false;
    }

    if (username.isEmpty) {
      _showError("Username is required");
      return false;
    }

    if (username.length < 3) {
      _showError("Username must be at least 3 characters");
      return false;
    }

    if (username.length > 20) {
      _showError("Username must be at most 20 characters");
      return false;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      _showError("Username can only contain letters, numbers, and underscores");
      return false;
    }

    if (phone.isEmpty) {
      _showError("Phone number is required");
      return false;
    }

    if (phone.length < 7) {
      _showError("Please enter a valid phone number");
      return false;
    }

    if (selectedDate == null) {
      _showError("Please select your birthdate");
      return false;
    }

    final today = DateTime.now();
    final age = today.year - selectedDate!.year;
    if (age < 13) {
      _showError("You must be at least 13 years old to use Swaply");
      return false;
    }

    return true;
  }

  /// 💾 Save profile updates to Supabase
  Future<void> _saveProfile() async {
    if (!_validateInput()) return;

    setState(() => isSaving = true);

    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) throw Exception("User session not found");

      print("📝 Updating profile for User ID: ${user.id}");

      final updates = {
        'full_name': fullNameController.text.trim(),
        'username': usernameController.text.trim(),
        'bio': bioController.text.trim(),
        'phone': phoneController.text.trim(),
        'gender': gender,
        'birthdate': selectedDate?.toIso8601String().split('T')[0],
        'updated_at': DateTime.now().toIso8601String(),
      };

      print("📦 Updating data: $updates");

      await SupabaseService.client
          .from('users')
          .update(updates)
          .eq('auth_user_id', user.id);

      if (!mounted) return;

      _showSuccess("✅ Profile updated successfully!");

      // 💡 Delay slightly before popping to show success message
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print("❌ SAVE ERROR: $e");
      String errorMsg = "Error: ${e.toString()}";

      if (e.toString().contains("permission denied")) {
        errorMsg = "Permission denied. Please check your account settings.";
      } else if (e.toString().contains("connection")) {
        errorMsg = "Network error. Please check your connection and try again.";
      } else if (e.toString().contains("duplicate")) {
        errorMsg = "This username is already taken. Please try another one.";
      }

      _showError(errorMsg);
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔄 Loading state
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F3F8),
        appBar: AppBar(
          title: const Text("Edit Profile"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // ❌ Error state
    if (loadError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F3F8),
        appBar: AppBar(
          title: const Text("Edit Profile"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(loadError ?? "Unknown error"),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadUserProfile,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ Form state
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text("Edit Profile"),
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
              // 📝 Full Name
              _buildSectionTitle("Full Name"),
              _InputField(
                controller: fullNameController,
                icon: Icons.person,
                hint: "Enter your full name",
              ),
              const SizedBox(height: 20),

              // 👤 Username
              _buildSectionTitle("Username"),
              _InputField(
                controller: usernameController,
                icon: Icons.account_circle,
                hint: "Enter your username",
              ),
              const SizedBox(height: 20),

              // 📧 Email (Read-only)
              _buildSectionTitle("Email Address"),
              _InputField(
                controller: emailController,
                icon: Icons.email,
                hint: "Email",
                readOnly: true,
              ),
              const SizedBox(height: 8),
              const Text(
                "Email cannot be changed",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // 📱 Phone
              _buildSectionTitle("Phone Number"),
              _InputField(
                controller: phoneController,
                icon: Icons.phone,
                hint: "Enter your phone number",
              ),
              const SizedBox(height: 20),

              // 🎂 Birthdate
              _buildSectionTitle("Birthdate"),
              GestureDetector(
                onTap: () => _pickDate(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7FB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.purple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          selectedDate == null
                              ? "Select Birthdate"
                              : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}",
                          style: TextStyle(
                            color: selectedDate == null ? Colors.grey : Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 🧑‍🤝‍🧑 Gender
              _buildSectionTitle("Gender"),
              Row(
                children: [
                  _GenderOption(
                    label: "Male",
                    selected: gender == "Male",
                    onTap: () => setState(() => gender = "Male"),
                  ),
                  const SizedBox(width: 10),
                  _GenderOption(
                    label: "Female",
                    selected: gender == "Female",
                    onTap: () => setState(() => gender = "Female"),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 💬 Bio
              _buildSectionTitle("Bio"),
              TextField(
                controller: bioController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "Tell us about yourself (optional)",
                  filled: true,
                  fillColor: const Color(0xFFF7F7FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // 💾 Save Button
              GestureDetector(
                onTap: isSaving ? null : _saveProfile,
                child: Container(
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: isSaving
                          ? [Colors.grey, Colors.grey]
                          : [const Color(0xFF7B61FF), const Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: Center(
                    child: isSaving
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Save Changes",
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

              // ✖️ Cancel Button
              GestureDetector(
                onTap: isSaving ? null : () => Navigator.pop(context),
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

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool readOnly;

  const _InputField({
    required this.controller,
    required this.icon,
    required this.hint,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
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
            border: Border.all(
              color: selected ? Colors.purple : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
