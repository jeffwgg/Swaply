import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/views/screens/profile/profile_tabs.dart';
import 'package:swaply/repositories/favourite_repository.dart';
import '/services/supabase_service.dart';
import '/services/profile_service.dart';
import '/services/follow_service.dart';
import '../auth/login_screen.dart';
import 'settings_screen.dart';
import '../../../models/app_user.dart';
import '../../../core/utils/app_snack_bars.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'followers_screen.dart';
import 'following_screen.dart';
import '../../../repositories/local/local_profile_repository.dart';

class ProfileScreen extends StatefulWidget {
  final String? viewingUserId; // If null, show current user's profile

  const ProfileScreen({super.key, this.viewingUserId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isFollowing = false;
  bool _isLoadingFollow = false;
  Future<Map<String, int>>? _statsFuture;
  String? _profileUserId;

  StreamSubscription? _followingStream;
  StreamSubscription? _followersStream;
  StreamSubscription? _favouritesStream;

  @override
  void initState() {
    super.initState();
    final user = SupabaseService.client.auth.currentUser;
      _profileUserId = widget.viewingUserId ?? user?.id;
      if (_profileUserId != null) {
        _statsFuture = _loadStatistics(_profileUserId!);
        _isOnline().then((online) {
          if (online && mounted) _setupFollowStreams();
        });
      }
    _checkFollowStatus();
  }
  void _setupFollowStreams() async{
    if (_profileUserId == null) return;

    final online = await _isOnline();
    if (!online) {
      _refreshStats();
      return;
    }

    try{
      _followingStream = SupabaseService.client
          .from('follows')
          .stream(primaryKey: ['id'])
          .eq('follower_id', _profileUserId!)
          .handleError((e) => print('Following stream error: $e'))
          .listen((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _refreshStats();
        });
      });

      _followersStream = SupabaseService.client
          .from('follows')
          .stream(primaryKey: ['id'])
          .eq('followee_id', _profileUserId!)
          .handleError((e) => print('Followers stream error: $e'))
          .listen((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _refreshStats();
        });
      });

      _favouritesStream = SupabaseService.client
          .from('favourites')
          .stream(primaryKey: ['id'])
          .handleError((e) => print('Favourites stream error: $e'))
          .listen(
            (_) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _refreshStats();
          });
        },
        onError: (e) => print('Favourites stream error: $e'),
      );
    }catch(e) {
      print('Stream setup error: $e');
    }
  }

  void _refreshStats() {
    if (_profileUserId == null) return;
    setState(() {
      _statsFuture = _loadStatistics(_profileUserId!);
    });
  }

  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _followingStream?.cancel();
    _followersStream?.cancel();
    _favouritesStream?.cancel();
    super.dispose();
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
    if (user == null) {
      return _buildGuestView(context);
    }
    if (user.emailConfirmedAt == null) {
      return _buildUnverifiedEmailView(context, user);
    }
    return _buildFullProfileView(context);
  }

  Widget _buildGuestView(BuildContext context) {
    return Scaffold(
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

  Widget _buildUnverifiedEmailView(BuildContext context, User user) {
    return Scaffold(
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
                  try {
                    await SupabaseService.client.auth.resend(
                      type: OtpType.signup,
                      email: user.email!,
                    );

                    if (context.mounted) {
                    AppSnackBars.success(context, 'Verification email resent! Check your inbox.');
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppSnackBars.error(context, 'Error: ${e.toString()}');
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

  Widget _buildFullProfileView(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    final profileUserId = widget.viewingUserId ?? user!.id;
    final isOwnProfile = profileUserId == user!.id;
    final localRepo = LocalProfileRepository();

    return FutureBuilder<AppUser?>(
      future: localRepo.getCachedProfile(profileUserId),
      builder: (context, cacheSnapshot) {
        return StreamBuilder<AppUser?>(
          stream: ProfileService.watchProfile(profileUserId),
          builder: (context, networkSnapshot) {
            if (networkSnapshot.hasData && networkSnapshot.data != null) {
              localRepo.saveProfile(networkSnapshot.data!);

              final imgUrl = networkSnapshot.data!.profileImage;
              if (imgUrl != null && imgUrl.isNotEmpty) {
                localRepo.cacheProfileImage(profileUserId, imgUrl).then((path){
              });
              }
            }

            final profile = networkSnapshot.data ?? cacheSnapshot.data;

            if (profile == null &&
                networkSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (networkSnapshot.hasError && profile == null) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                          Icons.error_outline, size: 60, color: Colors.red),
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

            if (profile == null) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                          Icons.person_outline, size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("Profile not found"),
                    ],
                  ),
                ),
              );
            }

            final fullName = profile.fullName ?? 'User';
            final username = profile.username ?? 'user';
            final bio = profile.bio ?? 'No bio yet';

            return Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // 🔝 TOP BAR
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20,
                            vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if(isOwnProfile)
                              const Text(
                                'Swaply',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF5A2CA0),
                                ),
                              )
                            else
                              GestureDetector(
                                onTap: () {
                                  if (Navigator.canPop(context)) Navigator.pop(
                                      context);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 8.0, horizontal: 4.0), // 增加点击区域
                                  child: Icon(Icons.arrow_back_ios_new,
                                      color: Color(0xFF5A2CA0)),
                                ),
                              ),

                            if (isOwnProfile)
                              IconButton(
                                icon: const Icon(Icons.settings_outlined,
                                    color: Color(0xFF5A2CA0)),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const SettingsScreen()),
                                  );
                                },
                              )
                            else
                              const SizedBox(width: 48),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      Column(
                        children: [
                          Stack(
                            children: [
                              FutureBuilder<String?>(
                                future: localRepo.getCachedImagePath(profileUserId),
                                builder: (context, imgSnapshot) {
                                  final localPath = imgSnapshot.data;
                                  final networkUrl = profile.profileImage;

                                  return FutureBuilder<bool>(
                                    future: _isOnline(),
                                    builder: (context, onlineSnapshot) {
                                      final isOnline = onlineSnapshot.data ?? true;

                                      ImageProvider? imageProvider;
                                      if (isOnline && networkUrl != null && networkUrl.isNotEmpty) {
                                        imageProvider = NetworkImage(
                                          '$networkUrl?t=${DateTime.now().millisecondsSinceEpoch}',
                                        );
                                      } else if (localPath != null) {
                                        imageProvider = FileImage(File(localPath));
                                      }

                                      return CircleAvatar(
                                        radius: 45,
                                        backgroundColor: Colors.purple,
                                        backgroundImage: imageProvider,
                                        child: imageProvider == null
                                            ? Text(
                                          profile.username[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                            : null,
                                      );
                                    },
                                  );
                                },
                              ),
                              if (isOwnProfile)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: _showImagePickerBottomSheet,
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
                            const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "@$username",
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            bio,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      FutureBuilder<Map<String, int>>(
                        future: _statsFuture,
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
                              border: Border.all(
                                  color: Colors.grey.withOpacity(0.2)),
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
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            FollowingScreen(
                                              userId: profileUserId,
                                              userName: fullName,
                                            ),
                                      ),
                                    ).then((_) => _refreshStats());
                                  },
                                ),
                                Container(width: 1,
                                    height: 40,
                                    color: Colors.grey[300]),
                                _StatColumn(
                                  value: stats['followers'].toString(),
                                  label: 'Followers',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            FollowersScreen(
                                              userId: profileUserId,
                                              userName: fullName,
                                            ),
                                      ),
                                    ).then((_) => _refreshStats());
                                  },
                                ),
                                Container(width: 1,
                                    height: 40,
                                    color: Colors.grey[300]),
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
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
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
                      const SizedBox(height: 20),

                      //tabs
                      SizedBox(
                        height: 400,
                        child: ProfileTabs(
                          userId: profileUserId,
                          isOwnProfile: isOwnProfile,
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
    final localRepo = LocalProfileRepository();
    final isOnline = await _isOnline();

    if (!isOnline) {
      final cached = await localRepo.getCachedStats(userId);
      return cached ?? {'following': 0, 'followers': 0, 'saved': 0};
    }

    try {
      final following = await FollowService.getFollowingCount(userId);
      final followers = await FollowService.getFollowerCount(userId);
      final saved = await FavouriteRepository().getTotalSavedForSeller(userId);

      final stats = {
        'following': following,
        'followers': followers,
        'saved': saved,
      };

      await localRepo.saveStats(userId, following, followers, saved);
      return stats;
    } catch (e) {
      final cached = await localRepo.getCachedStats(userId);
      return cached ?? {'following': 0, 'followers': 0, 'saved': 0};
    }
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
                  _uploadProfilePicture(isCamera: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.purple),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _uploadProfilePicture(isCamera: false);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  bool isValidImage(File file) {
    final ext = path.extension(file.path).toLowerCase();
    return ['.jpg', '.jpeg', '.png'].contains(ext);
  }

  Future<void> _uploadProfilePicture({required bool isCamera}) async {
    try {
      final File? imageFile = isCamera
          ? await ProfileService.pickImageFromCamera()
          : await ProfileService.pickImageFromGallery();

      if (imageFile == null) return;
      if (imageFile.lengthSync() > 2 * 1024 * 1024) {
        AppSnackBars.error(context, 'Image must be less than 2MB');
        return;
      }
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;

      if (!isValidImage(imageFile)) {
        if (mounted) {
          AppSnackBars.error(context, 'Only JPG, JPEG, PNG images are allowed');
        }
        return;
      }

      final url = await ProfileService.uploadProfilePicture(imageFile, user.id);
      if (url != null && mounted) {
        AppSnackBars.success(context, 'Profile picture updated!');
        setState(() {});
      } else if (mounted) {
        AppSnackBars.error(context, 'Failed to upload profile picture');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.error(context, 'Error uploading profile picture');
      }
    }
  }

  Future<void> _toggleFollowUser() async {
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser == null || widget.viewingUserId == null) return;

    setState(() => _isLoadingFollow = true);

    try {
      if (_isFollowing) {
        await FollowService.unfollowUser(currentUser.id, widget.viewingUserId!);
        setState(() => _isFollowing = false);
        _refreshStats(); 
        if (mounted) {
          AppSnackBars.info(context, 'Unfollowed!');
        }
      } else {
        await FollowService.followUser(currentUser.id, widget.viewingUserId!);
        setState(() => _isFollowing = true);
         _refreshStats();
        if (mounted) {
          AppSnackBars.success(context, 'Following!');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.error(context, 'Error updating follow status');
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
  final VoidCallback? onTap;

  const _StatColumn({
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
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

    if (onTap == null) {
      return content;
    }

    return GestureDetector(
      onTap: onTap,
      child: content,
    );
  }
}
