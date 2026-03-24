import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/common/bottom_nav_bar.dart';
import '../screens/home/home_screen.dart';
import '../screens/explore/discover_screen.dart';
import '../screens/chat/inbox_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/item/create_item_screen.dart';
import '../../core/theme/app_colors.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _hideChatNavigation = false;

  void _onNavTap(int index) {
    setState(() {
      _currentIndex = index;
      if (index != 2) {
        _hideChatNavigation = false;
      }
    });
  }

  void _onAddTap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateItemScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const DiscoverScreen(),
      InboxScreen(
        onConversationViewChanged: (isConversationOpen) {
          if (_hideChatNavigation == isConversationOpen) {
            return;
          }

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
        body: screens[_currentIndex],

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
