import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import '../main_shell.dart';
import 'dart:io';
import '../../../services/profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  File? _profileImage;
  @override
  void dispose() {
    usernameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    fullNameController.dispose();
    bioController.dispose();
    super.dispose();
  }

  void _showImagePickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose Profile Picture',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.purple),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage(isCamera: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.purple),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage(isCamera: false);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // 🖼️ 获取图片
  Future<void> _pickProfileImage({required bool isCamera}) async {
    try {
      final File? imageFile = isCamera
          ? await ProfileService.pickImageFromCamera()
          : await ProfileService.pickImageFromGallery();

      if (imageFile == null) return;

      if (imageFile.lengthSync() > 2 * 1024 * 1024) {
        _showError('Image must be less than 2MB');
        return;
      }

      setState(() {
        _profileImage = imageFile;
      });
    } catch (e) {
      _showError('Error picking image: $e');
    }
  }
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _saveProfile() async {
    if (isSaving) {
      return;
    }
    setState(() => isSaving = true);

    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) {
        _showError("Your sign-in session expired. Please log in again.");
        return;
      }
      final email = user.email;
      if (email == null || email.trim().isEmpty) {
        _showError("Your account email is unavailable. Please log in again.");
        return;
      }

      final error = await ProfileService.createProfile(
        userId: user.id,
        email: email,
        username: usernameController.text.trim(),
        fullName: fullNameController.text.trim(),
        bio: bioController.text.trim(),
        phone: phoneController.text.trim(),
        gender: gender,
        birthdate: selectedDate,
      );

      if (error != null) {
        _showError(error);
        return;
      }

      if (_profileImage != null) {
        await ProfileService.uploadProfilePicture(_profileImage!, user.id);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile setup complete! Welcome to Swaply."),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } on AuthException catch (e) {
      debugPrint("Profile setup auth error: ${e.message}");
      _showError(e.message);
    } on PostgrestException catch (e) {
      debugPrint("Profile setup database error: ${e.message}");
      _showError(e.message);
    } catch (e) {
      debugPrint("Profile setup error: $e");
      _showError("Something went wrong: $e");
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

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

    if (!ProfileService.isValidPhoneNumber(phone)) {
      _showError("Phone number must be 11-12 digits and contain only numbers");
      return;
    }

    if (selectedDate == null) {
      _showError("Please select your birthdate");
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

              GestureDetector(
                onTap:_showImagePickerBottomSheet,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                      child: _profileImage == null
                          ? const Icon(Icons.person, size: 50, color: Colors.grey)
                          : null,
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
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 📦 CARD
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _InputField(
                      controller: usernameController,
                      icon: Icons.person,
                      hint: "Username",
                    ),
                    const SizedBox(height: 12),
                    _InputField(
                      controller: fullNameController,
                      icon: Icons.badge,
                      hint: "Full Name",
                    ),
                    const SizedBox(height: 12),
                    _InputField(
                      controller: bioController,
                      icon: Icons.edit,
                      hint: "Bio",
                    ),
                    const SizedBox(height: 12),
                    _InputField(
                      controller: phoneController,
                      icon: Icons.phone,
                      hint: "Phone Number",
                    ),
                    const SizedBox(height: 12),
                    _InputField(
                      controller: addressController,
                      icon: Icons.location_on,
                      hint: "Address",
                    ),
                    const SizedBox(height: 12),

                    _buildDatePicker(),
                    const SizedBox(height: 16),

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

  Widget _buildAvatarSection() {
    return Stack(
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
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.purple,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () => _pickDate(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today),
            const SizedBox(width: 10),
            Text(
              selectedDate == null
                  ? "Select Birthdate"
                  : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderPicker() {
    return Row(
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
              style: TextStyle(color: selected ? Colors.white : Colors.purple),
            ),
          ),
        ),
      ),
    );
  }
}
