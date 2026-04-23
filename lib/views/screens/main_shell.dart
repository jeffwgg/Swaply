import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_user.dart';
import '../../repositories/users_repository.dart';
import '../widgets/common/bottom_nav_bar.dart';
import '../screens/home/home_screen.dart';

import '../screens/explore/discover_screen.dart';
import '../screens/chat/inbox_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/item/create_item_screen.dart';
import 'auth/login_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../../services/supabase_service.dart';
import '../../../services/notification_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _hideChatNavigation = false;
  AppUser? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final authUser = SupabaseService.client.auth.currentUser;
    if (authUser == null) return;

    final user = await UsersRepository().getById(authUser.id);

    setState(() {
      _user = user;
    });
  }

  void _onNavTap(int index) {
    setState(() {
     if (index >= 4) return; 

    _currentIndex = index;

    if (index != 2) {
      _hideChatNavigation = false;
    }
    });
    NotificationService.instance.setChatTabActive(index == 2);
  }

  void _onAddTap() {
    final user = SupabaseService.client.auth.currentUser;

    // Not logged in
    if (user == null) {
      _showLoginPrompt("Please log in to start swapping items!");
      return;
    }

    // ⏳ Email not verified (maybe can be deleted later)
    if (user.emailConfirmedAt == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Email Not Verified"),
          content: const Text(
            "Please verify your email address before creating items. "
            "Check your inbox for the verification link.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    // User is verified, proceed to create item
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateItemScreen(user: _user!)),
    );
  }

  void _showLoginPrompt(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Login Required"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Maybe Later"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Log In / Register", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    NotificationService.instance.setChatTabActive(_currentIndex == 2);
    final screens = [
      SwipeHomeScreen(user: _user),
      DiscoverScreen(
        user: _user
      ),
      InboxScreen(
        onConversationViewChanged: (isConversationOpen) {
          if (_hideChatNavigation == isConversationOpen) return;
          setState(() => _hideChatNavigation = isConversationOpen);
        },
      ),
      const ProfileScreen(),
    ];

    final shouldShowShellNav = !(_currentIndex == 2 && _hideChatNavigation);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F7FF),
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex < screens.length ? _currentIndex : 0,
          children: screens,
        ),
        floatingActionButton: shouldShowShellNav
            ? _GlowFab(onTap: _onAddTap)
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: shouldShowShellNav
            ? BottomNavBar(currentIndex: _currentIndex, onTap: _onNavTap)
            : null,
      ),
      
    );
    
  }
  
}

class _GlowFab extends StatelessWidget {
  final VoidCallback onTap;
  const _GlowFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary,
          boxShadow: [
            // inner glow
            BoxShadow(
              color: AppColors.primaryLight.withValues(alpha: 0.55),
              blurRadius: 18,
              spreadRadius: 3,
            ),
            // outer glow
            BoxShadow(
              color: AppColors.primaryLight.withValues(alpha: 0.25),
              blurRadius: 36,
              spreadRadius: 8,
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 34),
      ),
    );
  }
}
