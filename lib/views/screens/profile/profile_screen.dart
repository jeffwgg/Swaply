import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/services/supabase_service.dart';
import '/services/profile_service.dart';
import '/services/follow_service.dart';
import '/services/saved_items_service.dart';
import '../auth/login_screen.dart';
import 'settings_screen.dart';
import '../../../models/app_user.dart';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  final String? viewingUserId; // If null, show current user's profile

  const ProfileScreen({super.key, this.viewingUserId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isFollowing = false;
  bool _isLoadingFollow = false;

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser != null && widget.viewingUserId != null) {
      final following =
          await FollowService.isFollowing(currentUser.id, widget.viewingUserId!);
      setState(() => _isFollowing = following);
    }
  }

  @override
  Widget build(BuildContext context) {

    final user = SupabaseService.client.auth.currentUser;
    print("🔥 NEW PROFILE SCREEN RUNNING");
  
    if (user == null) {
      return _buildGuestView(context);
    }

    if (user.emailConfirmedAt == null) {
      return _buildUnverifiedEmailView(context, user);
    }

    return _buildFullProfileView(context);
  }

  // --- 1. (Guest View) ---
  Widget _buildGuestView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline, size: 60, color: Colors.purple),
              ),
              const SizedBox(height: 24),
              const Text(
                "Welcome to Swaply",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Log in to see your profile, manage listings, and start swapping!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Container(
                  height: 50,
                  width: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B61FF), Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      "Login / Register",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

  // --- 1.5. (Unverified Email View) ---
  Widget _buildUnverifiedEmailView(BuildContext context, User user) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mail_outline, size: 60, color: Colors.orange),
              ),
              const SizedBox(height: 24),
              const Text(
                "Verify Your Email",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "A verification link has been sent to ${user.email}.\n\nPlease check your email and click the link to verify your account.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () async {
                  // 重新发送验证邮件
                  try {
                    await SupabaseService.client.auth.resend(
                      type: OtpType.signup,
                      email: user.email!,
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Verification email resent! Check your inbox."),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Error: ${e.toString()}")),
                      );
                    }
                  }
                },
                child: Container(
                  height: 50,
                  width: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B61FF), Color(0xFF5A3FFF)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      "Resend Email",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

  // --- 2. Verified User View (Full Profile) ---
  Widget _buildFullProfileView(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    final profileUserId = widget.viewingUserId ?? user!.id;
    final isOwnProfile = profileUserId == user!.id;

    return FutureBuilder<AppUser?>(
      future: ProfileService.getProfile(profileUserId),

      builder: (context, snapshot) {  

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ❌ Error
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text("Failed to load profile"),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Go Back"),
                  ),
                ],
              ),
            ),
          );
        }

        final profile = snapshot.data;

        if (profile == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline, size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("Profile not found"),
                ],
              ),
            ),
          );
        }

        // ✅ Data loaded successfully
        final fullName = profile.fullName ?? 'User';
        final username = profile.username ?? 'user';
        final bio = profile.bio ?? 'No bio yet';
        final email = profile.email ?? '';
        final phone = profile.phone ?? '';

          return Scaffold(
          backgroundColor: const Color(0xFFF4F3F8),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 🔝 TOP BAR
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.arrow_back_ios_new),
                        ),
                        Text(
                          fullName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (isOwnProfile)
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                            },
                          )
                        else
                          const SizedBox(width: 40),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 👤 PROFILE SECTION
                  Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.purple,
                            child: Text(
                              profile.username[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isOwnProfile)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () {
                                  // _showImagePickerBottomSheet();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.purple,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fullName,
                        style:
                            const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "@$username",
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.yellow.withOpacity(0.3),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.star, size: 12, color: Colors.white),
                                SizedBox(width: 2),
                                Text(
                                  '4.5/5',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 📊 STATISTICS ROW (Following, Followers, Saved Items)
                  FutureBuilder<Map<String, int>>(
                    future: _loadStatistics(profileUserId),
                    builder: (context, statsSnapshot) {
                      if (!statsSnapshot.hasData) {
                        return const SizedBox(height: 80);
                      }

                      final stats = statsSnapshot.data!;

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.05),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatColumn(
                              value: stats['following'].toString(),
                              label: 'Following',
                            ),
                            Container(width: 1, height: 40, color: Colors.grey[300]),
                            _StatColumn(
                              value: stats['followers'].toString(),
                              label: 'Followers',
                            ),
                            Container(width: 1, height: 40, color: Colors.grey[300]),
                            _StatColumn(
                              value: stats['saved'].toString(),
                              label: 'Total Saved',
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // ➕ FOLLOW/UNFOLLOW BUTTON (if viewing another user's profile)
                  if (!isOwnProfile)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _isLoadingFollow ? null : _toggleFollowUser,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isFollowing
                                ? Colors.grey[300]
                                : const Color(0xFF5A2CA0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isLoadingFollow
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isFollowing ? 'Following ✓' : 'Follow +',
                                  style: TextStyle(
                                    color: _isFollowing
                                        ? Colors.black87
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ℹ️ INFO SECTION
                  // Container(
                  //   margin: const EdgeInsets.symmetric(horizontal: 16),
                  //   padding: const EdgeInsets.all(16),
                  //   decoration: BoxDecoration(
                  //     color: Colors.white,
                  //     borderRadius: BorderRadius.circular(16),
                  //     border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  //   ),
                  //   child: Column(
                  //     crossAxisAlignment: CrossAxisAlignment.start,
                  //     children: [
                  //       const Text(
                  //         "Contact Information",
                  //         style: TextStyle(fontWeight: FontWeight.bold),
                  //       ),
                  //       const SizedBox(height: 12),
                  //       _buildInfoRow(Icons.email, "Email", email),
                  //       const SizedBox(height: 12),
                  //       _buildInfoRow(Icons.phone, "Phone", phone.isEmpty ? "Not set" : phone),
                  //     ],
                  //   ),
                  // ),

                  const SizedBox(height: 20),

                  // 📂 TABS
                  DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        const TabBar(
                          labelColor: Colors.purple,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Colors.purple,
                          tabs: [
                            Tab(text: "Listings"),
                            Tab(text: "Reviews"),
                            Tab(text: "About"),
                          ],
                        ),
                        SizedBox(
                          height: 300,
                          child: TabBarView(
                            children: [
                              const _Listings(),
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text("No reviews yet"),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  bio.isNotEmpty ? bio : "No bio provided",
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.purple, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Future<Map<String, int>> _loadStatistics(String userId) async {
    final following = await FollowService.getFollowingCount(userId);
    final followers = await FollowService.getFollowerCount(userId);
    final saved = await SavedItemsService.getTotalSavedCount(userId);

    return {
      'following': following,
      'followers': followers,
      'saved': saved,
    };
  }

  // void _showImagePickerBottomSheet() {
  //   showModalBottomSheet(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return Container(
  //         padding: const EdgeInsets.all(20),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             const Text(
  //               'Choose Profile Picture',
  //               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  //             ),
  //             const SizedBox(height: 20),
  //             ListTile(
  //               leading: const Icon(Icons.camera_alt, color: Colors.purple),
  //               title: const Text('Take a Photo'),
  //               onTap: () {
  //                 Navigator.pop(context);
  //                 _uploadProfilePicture(isCamera: true);
  //               },
  //             ),
  //             ListTile(
  //               leading: const Icon(Icons.image, color: Colors.purple),
  //               title: const Text('Choose from Gallery'),
  //               onTap: () {
  //                 Navigator.pop(context);
  //                 _uploadProfilePicture(isCamera: false);
  //               },
  //             ),
  //             const SizedBox(height: 10),
  //           ],
  //         ),
  //       );
  //     },
  //   );
  // }

  // Future<void> _uploadProfilePicture({required bool isCamera}) async {
  //   try {
  //     final File? imageFile = isCamera
  //         ? await ProfileService.pickImageFromCamera()
  //         : await ProfileService.pickImageFromGallery();

  //     if (imageFile == null) return;

  //     final user = SupabaseService.client.auth.currentUser;
  //     if (user == null) return;

  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('Uploading profile picture...')),
  //     );

  //     final url = await ProfileService.uploadProfilePicture(imageFile, user.id);

  //     if (url != null && mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Profile picture updated!'),
  //           backgroundColor: Colors.green,
  //         ),
  //       );
  //       // Refresh the UI
  //       setState(() {});
  //     } else if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Failed to upload profile picture'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     print('Error uploading profile picture: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Error uploading profile picture'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  Future<void> _toggleFollowUser() async {
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser == null || widget.viewingUserId == null) return;

    setState(() => _isLoadingFollow = true);

    try {
      if (_isFollowing) {
        await FollowService.unfollowUser(currentUser.id, widget.viewingUserId!);
        setState(() => _isFollowing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unfollowed!')),
          );
        }
      } else {
        await FollowService.followUser(currentUser.id, widget.viewingUserId!);
        setState(() => _isFollowing = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Following!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error toggling follow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error updating follow status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingFollow = false);
      }
    }
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;

  const _StatColumn({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF5A2CA0),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

class _Listings extends StatelessWidget {
  const _Listings();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text("Active Listings", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("View All", style: TextStyle(color: Colors.purple)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                _ItemCard(),
                SizedBox(width: 10),
                _ItemCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey[200],
      ),
      child: Column(
        children: const [
          Expanded(child: Icon(Icons.image, size: 60)),
          Padding(
            padding: EdgeInsets.all(6),
            child: Text("RM120.00", style: TextStyle(color: Colors.purple)),
          )
        ],
      ),
    );
  }
}