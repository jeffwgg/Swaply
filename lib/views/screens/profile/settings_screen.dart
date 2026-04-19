import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'help_center_screen.dart';
import 'about_app_screen.dart';


class SettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  bool notifications = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // 👤 ACCOUNT
          _SectionTitle("Account"),
          _Tile(Icons.person, "Edit Profile", onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            );
          }),
          _Tile(Icons.lock, "Change Password", onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            );
          }),

          const SizedBox(height: 20),

          // ⚙️ PREFERENCES
          _SectionTitle("Preferences"),

          SwitchListTile(
            title: const Text("Dark Mode"),
            value: widget.isDarkMode,
            activeColor: Colors.purple,
            onChanged: (value) {
              widget.onThemeChanged(value);
              setState(() {});
            },
          ),

          SwitchListTile(
            title: const Text("Notifications"),
            value: notifications,
            activeColor: Colors.purple,
            onChanged: (value) {
              setState(() => notifications = value);
            },
          ),

          const SizedBox(height: 20),

          // ❓ SUPPORT
          _SectionTitle("Support"),
          _Tile(Icons.help_outline, "Help Center", onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
            );
          }),
          _Tile(Icons.info_outline, "About App", onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutAppScreen()),
            );
          }),

          const SizedBox(height: 30),

          // 🔴 LOGOUT
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout", style: TextStyle(color: Colors.red)),
            onTap: () async {
              print("🔴 Logout clicked");

              bool? confirm = await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Logout"),
                  content: const Text("Are you sure you want to logout?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Logout", style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );

              if (confirm == true && mounted) {
                try {
                  // Show loading
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Dialog(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text("Logging out..."),
                          ],
                        ),
                      ),
                    ),
                  );

                  // Perform logout
                  print("🔐 Signing out from Supabase...");
                  await SupabaseService.logout();

                  print("✅ Logout successful!");

                  // Close loading dialog
                  if (mounted) Navigator.pop(context);

                  // Show success message
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("✅ You've been logged out successfully"),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }

                  // AuthGate will automatically handle the navigation back to guest mode
                  // No need to manually navigate - the auth stream will trigger a rebuild
                } catch (e) {
                  print("❌ Logout error: $e");

                  // Close loading dialog if still open
                  if (mounted) {
                    try {
                      Navigator.pop(context);
                    } catch (_) {}
                  }

                  // Show error
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("❌ Logout failed: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// 🔹 SECTION TITLE
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}

// 🔹 TILE
class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _Tile(this.icon, this.title, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}