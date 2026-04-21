import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/services/supabase_service.dart';
import '/services/profile_service.dart';

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
  String? originalUsername;
  String? originalPhone;
  bool isUsernameLocked = false;
  bool isGenderLocked = false;
  bool isBirthdateLocked = false;
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

    final profile = await ProfileService.getProfile(user.id);

    if (!mounted) return;

    if (profile == null) {
      throw Exception("Profile not found");
    }

    print("📝 Loading profile for User ID: ${user.id}");

    final metadata = user.userMetadata ?? <String, dynamic>{};
    final usernameChangedFlag =
        metadata['username_changed'] == true ||
        metadata['username_changed'] == 'true';

    setState(() {
      fullNameController.text = profile.fullName ?? '';
      usernameController.text = profile.username ?? '';
      originalUsername = profile.username ?? '';
      bioController.text = profile.bio ?? '';
      phoneController.text = profile.phone ?? '';
      originalPhone = profile.phone ?? '';
      emailController.text = profile.email ?? '';
      gender = profile.gender ?? 'Male';

      isGenderLocked = profile.gender != null;
      isBirthdateLocked = profile.birthdate != null;
      isUsernameLocked = usernameChangedFlag;

      if (profile.birthdate != null) {
        selectedDate = profile.birthdate;
      }

      isLoading = false;
    });
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
    if (isBirthdateLocked) {
      _showError('Birthdate cannot be changed after initial setup.');
      return;
    }

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

    // ✅ NEW: Full name must not contain numbers
    if (!ProfileService.isValidFullName(fullName)) {
      _showError("Full name must contain only letters and spaces (no numbers)");
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

    // ✅ UPDATED: Username max 10 characters (was 20)
    if (username.length > 10) {
      _showError("Username must be at most 10 characters");
      return false;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      _showError("Username can only contain letters, numbers, and underscores");
      return false;
    }

    if (originalUsername != null && isUsernameLocked && username != originalUsername) {
      _showError("Username can only be changed once.");
      return false;
    }

    if (phone.isEmpty) {
      _showError("Phone number is required");
      return false;
    }

    // ✅ UPDATED: Phone validation 10-12 digits (was 11-12)
    if (!ProfileService.isValidPhoneNumber(phone)) {
      _showError("Phone number must be 10-12 digits and contain only numbers (e.g. 0123456789 or 012345678901)");
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

  Future<void> _saveProfile() async {
    if (!_validateInput()) return;

    setState(() => isSaving = true);

    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) throw Exception("User session not found");

      final currentUsername = usernameController.text.trim();

      // ✅ Phone duplicate still here (you already moved to service)
      final currentPhone = phoneController.text.trim();
      if (originalPhone != null && currentPhone != originalPhone) {
        final isPhoneDuplicated = await ProfileService.isPhoneDuplicate(
          currentPhone,
          user.id,
        );

        if (isPhoneDuplicated) {
          _showError("This phone number is already registered to another account");
          return;
        }
      }

      final updates = {
        'full_name': fullNameController.text.trim(),
        'username': currentUsername,
        'bio': bioController.text.trim(),
        'phone': phoneController.text.trim(),
        'gender': gender,
        'birthdate': selectedDate?.toIso8601String().split('T')[0],
        'updated_at': DateTime.now().toIso8601String(),
      };

      // 🔥 CALL SERVICE HERE
      final error = await ProfileService.updateProfile(
        userId: user.id,
        updates: updates,
        originalUsername: originalUsername,
        currentUsername: currentUsername,
        isUsernameLocked: isUsernameLocked,
      );

      if (error != null) {
        if (error == "USERNAME_TAKEN") {
          _showError("This username is already taken. Please choose another one.");
        } else {
          _showError("Error updating profile");
        }
        return;
      }

      if (!mounted) return;

      _showSuccess("✅ Profile updated successfully!");

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        // ✅ Return true to indicate successful update
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError("Error updating profile");
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
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
              ),
              const SizedBox(height: 20),

              // 👤 Username
              _buildSectionTitle("Username"),
              _InputField(
                controller: usernameController,
                icon: Icons.account_circle,
                hint: "Enter your username",
                readOnly: isUsernameLocked,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(10),
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isUsernameLocked
                    ? "Username can only be changed once and is now locked."
                    : "You can update your username one time. Choose carefully.",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                inputFormatters: [
                  LengthLimitingTextInputFormatter(12),
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Phone number must be 10-12 digits (e.g. 0123456789 or 012345678901)",
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
              const SizedBox(height: 8),
              if (isBirthdateLocked)
                const Text(
                  "Birthdate cannot be changed after initial setup.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const SizedBox(height: 20),

              // 🧑‍🤝‍🧑 Gender
              _buildSectionTitle("Gender"),
              Row(
                children: [
                  _GenderOption(
                    label: "Male",
                    selected: gender == "Male",
                    onTap: () {
                      if (isGenderLocked) return;
                      setState(() => gender = "Male");
                    },
                  ),
                  const SizedBox(width: 10),
                  _GenderOption(
                    label: "Female",
                    selected: gender == "Female",
                    onTap: () {
                      if (isGenderLocked) return;
                      setState(() => gender = "Female");
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isGenderLocked)
                const Text(
                  "Gender cannot be changed after initial setup.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
  final List<TextInputFormatter>? inputFormatters;

  const _InputField({
    required this.controller,
    required this.icon,
    required this.hint,
    this.readOnly = false,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      inputFormatters: inputFormatters,
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
