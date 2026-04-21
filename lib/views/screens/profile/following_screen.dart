import 'package:flutter/material.dart';
import 'package:swaply/models/app_user.dart';
import 'package:swaply/services/follow_service.dart';
import 'package:swaply/services/supabase_service.dart';
import 'profile_screen.dart';

class FollowingScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const FollowingScreen({
    required this.userId,
    required this.userName,
    super.key,
  });

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  late Future<List<AppUser>> _followingFuture;
  Map<String, bool> _followingState = {};
  Set<String> _loadingIds = {};

  @override
  void initState() {
    super.initState();
    _followingFuture = _loadFollowing();
  }

  Future<List<AppUser>> _loadFollowing() async {
    try {
      final followingData = await FollowService.getFollowing(widget.userId);
      final users = <AppUser>[];
      
      for (var followData in followingData) {
        final followeeObj = followData['followee'] as Map<String, dynamic>?;
        if (followeeObj != null) {
          try {
            final user = AppUser(
              id: followeeObj['id'] as String,
              username: followeeObj['username'] as String? ?? 'Unknown',
              email: '',
              profileImage: followeeObj['profile_image'] as String?,
              createdAt: DateTime.now(),
            );
            users.add(user);
            
            // Check if current user is following this person
            final currentUser = SupabaseService.client.auth.currentUser;
            if (currentUser != null) {
              final isFollowing = await FollowService.isFollowing(currentUser.id, user.id);
              setState(() => _followingState[user.id] = isFollowing);
            }
          } catch (e) {
            print('Error parsing following user: $e');
          }
        }
      }
      
      return users;
    } catch (e) {
      print('Error loading following: $e');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
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
        title: Text("${widget.userName}'s Following"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _followingFuture,
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
                  const Text("Failed to load following"),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _followingFuture = _loadFollowing();
                      });
                    },
                    child: const Text("Retry"),
                  ),
                ],
              ),
            );
          }

          final following = snapshot.data ?? [];

          if (following.isEmpty) {
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
                    "Not following anyone yet",
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
            itemCount: following.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final followingUser = following[index];
              final isFollowing = _followingState[followingUser.id] ?? false;
              final isLoading = _loadingIds.contains(followingUser.id);
              final currentUser = SupabaseService.client.auth.currentUser;
              final isOwnProfile = currentUser?.id == followingUser.id;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.purple,
                  backgroundImage: followingUser.profileImage != null
                      ? NetworkImage(followingUser.profileImage!)
                      : null,
                  child: followingUser.profileImage == null
                      ? Text(
                          followingUser.username[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  followingUser.username,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(viewingUserId: followingUser.id),
                    ),
                  );
                },
                trailing: !isOwnProfile && currentUser != null
                    ? SizedBox(
                        width: 100,
                        child: ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () => _toggleFollow(followingUser),
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
