import 'package:flutter/material.dart';
import 'package:swaply/core/utils/app_snack_bars.dart';
import 'package:swaply/models/app_user.dart';
import 'package:swaply/services/follow_service.dart';
import 'package:swaply/services/supabase_service.dart';
import 'profile_screen.dart';

class FollowersScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const FollowersScreen({
    required this.userId,
    required this.userName,
    super.key,
  });

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  late Future<List<AppUser>> _followersFuture;
  Map<String, bool> _followingState = {};
  Set<String> _loadingIds = {};

  @override
  void initState() {
    super.initState();
    _followersFuture = _loadFollowers();
  }

  Future<List<AppUser>> _loadFollowers() async {
    try {
      final followersData = await FollowService.getFollowers(widget.userId);
      final users = <AppUser>[];

      for (var followerData in followersData) {
        final followerObj = followerData['follower'] as Map<String, dynamic>?;
        if (followerObj != null) {
          try {
            // Parse created_at - use now() as fallback if not available
            DateTime createdAt = DateTime.now();
            if (followerObj['created_at'] != null) {
              try {
                createdAt = DateTime.parse(followerObj['created_at'] as String);
              } catch (e) {
                print('Error parsing created_at: $e');
              }
            }

            final user = AppUser(
              id: followerObj['id'] as String? ?? '',
              username: followerObj['username'] as String? ?? 'Unknown',
              email: followerObj['email'] as String? ?? '',
              profileImage: followerObj['profile_image'] as String?,
              createdAt: createdAt,
            );

            if (user.id.isNotEmpty) {
              users.add(user);

              final currentUser = SupabaseService.client.auth.currentUser;
              if (currentUser != null) {
                final isFollowing = await FollowService.isFollowing(currentUser.id, user.id);
                if (mounted) {
                  setState(() => _followingState[user.id] = isFollowing);
                }
              }
            }
          } catch (e) {
            print('Error parsing follower: $e');
          }
        }
      }

      return users;
    } catch (e) {
      print('Error loading followers: $e');
      return [];
    }
  }

  Future<void> _toggleFollow(AppUser user) async {
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser == null) return;

    setState(() => _loadingIds.add(user.id));
    
    try {
      final isCurrentlyFollowing = _followingState[user.id] ?? false;
      
      if (isCurrentlyFollowing) {
        await FollowService.unfollowUser(currentUser.id, user.id);
        setState(() => _followingState[user.id] = false);
      } else {
        await FollowService.followUser(currentUser.id, user.id);
        setState(() => _followingState[user.id] = true);
      }
    } catch (e) {
      print('Error toggling follow: $e');
      if (mounted) {
        AppSnackBars.error(context, 'Error: ${e.toString()}');
      }
    } finally {
      setState(() => _loadingIds.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: Text("${widget.userName}'s Followers"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _followersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text("Failed to load followers"),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _followersFuture = _loadFollowers();
                      });
                    },
                    child: const Text("Retry"),
                  ),
                ],
              ),
            );
          }

          final followers = snapshot.data ?? [];

          if (followers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No followers yet",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: followers.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final follower = followers[index];
              final isFollowing = _followingState[follower.id] ?? false;
              final isLoading = _loadingIds.contains(follower.id);
              final currentUser = SupabaseService.client.auth.currentUser;
              final isOwnProfile = currentUser?.id == follower.id;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.purple,
                  backgroundImage: follower.profileImage != null
                      ? NetworkImage('${follower.profileImage!}?t=${DateTime.now().millisecondsSinceEpoch}')
                      : null,
                  child: follower.profileImage == null
                      ? Text(
                          follower.username[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  follower.username,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(viewingUserId: follower.id),
                    ),
                  );
                },
                trailing: !isOwnProfile && currentUser != null
                    ? SizedBox(
                        width: 100,
                        child: ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () => _toggleFollow(follower),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFollowing
                                ? Colors.grey[300]
                                : const Color(0xFF5A2CA0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  isFollowing ? 'Following' : 'Follow',
                                  style: TextStyle(
                                    color: isFollowing
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
