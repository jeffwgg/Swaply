import 'package:flutter/material.dart';
import '/services/supabase_service.dart';
import '../../../core/utils/app_snack_bars.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'help_center_screen.dart';
import 'about_app_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  bool notifications = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          _SectionTitle("Account"),
          _Tile(Icons.person, "Edit Profile", onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            );

            if (result == true && mounted) {
              Navigator.pop(context, true);
            }
          }),
          _Tile(Icons.lock, "Change Password", onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            );
          }),

          const SizedBox(height: 20),

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

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout", style: TextStyle(color: Colors.red)),
            onTap: () async {
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
                  await SupabaseService.logout();
                  if (mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (route) => false,
                    );
                  }
                } catch (e) {
                  // Show error message
                  if (mounted) {
                    AppSnackBars.error(context, 'Logout failed: $e');
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