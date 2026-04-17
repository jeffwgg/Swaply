// import 'package:flutter/material.dart';
// import '/services/supabase_service.dart';
// import 'login_screen.dart';
// import 'profile_setup_screen.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

// class VerifyEmailScreen extends StatefulWidget {
//   const VerifyEmailScreen({super.key});

//   @override
//   State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
// }

// class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
//   bool isChecking = false;
//   bool isResending = false;

//   void _showError(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message)),
//     );
//   }

//   Future<void> _checkVerification() async {
//     setState(() => isChecking = true);

//     try {
//       final user = SupabaseService.client.auth.currentUser;

//       if (user == null) {
//         _showError("Session expired, please login again");
//         return;
//       }

//       // 🔥 关键：主动 fetch 最新 user
//       final response = await SupabaseService.client.auth.getUser();

//       final refreshedUser = response.user;

//       if (refreshedUser != null && refreshedUser.emailConfirmedAt != null) {
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(
//             builder: (_) => const ProfileSetupScreen(),
//           ),
//         );
//       } else {
//         _showError("Please verify your email first");
//       }

//     } catch (e) {
//       print("VERIFY ERROR: $e");
//       _showError("Verification failed");
//     }

//     setState(() => isChecking = false);
//   }

//   Future<void> _resendEmail() async {
//     setState(() => isResending = true);

//     try {
//       final email = SupabaseService.client.auth.currentUser?.email;

//       if (email != null) {
//         await SupabaseService.client.auth.resend(
//           type: OtpType.signup,
//           email: email,
//         );

//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text("Verification email sent again")),
//         );
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("Please wait before retrying")),
//       );
//     }

//     setState(() => isResending = false);
//   }

//   Future<void> _cancelAndLogout() async {
//     await SupabaseService.client.auth.signOut();

//     Navigator.pushAndRemoveUntil(
//       context,
//       MaterialPageRoute(builder: (_) => const LoginScreen()),
//           (route) => false,
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF4F3F8),

//       // 🔥 Back Button（关键）
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back, color: Colors.black),
//           onPressed: _cancelAndLogout,
//         ),
//       ),

//       body: Center(
//         child: Padding(
//           padding: const EdgeInsets.all(24),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [

//               const Icon(Icons.mark_email_read, size: 80, color: Colors.purple),

//               const SizedBox(height: 20),

//               const Text(
//                 "Verify Your Email",
//                 style: TextStyle(
//                   fontSize: 22,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),

//               const SizedBox(height: 10),

//               const Text(
//                 "We’ve sent a verification link to your email.\nPlease check and confirm.",
//                 textAlign: TextAlign.center,
//                 style: TextStyle(color: Colors.grey),
//               ),

//               const SizedBox(height: 30),

//               // ✅ VERIFY BUTTON
//               ElevatedButton(
//                 onPressed: isChecking ? null : _checkVerification,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.purple,
//                   minimumSize: const Size(double.infinity, 50),
//                 ),
//                 child: isChecking
//                     ? const CircularProgressIndicator(color: Colors.white)
//                     : const Text("I have verified"),
//               ),

//               const SizedBox(height: 10),

//               // 🔁 RESEND EMAIL
//               TextButton(
//                 onPressed: isResending ? null : _resendEmail,
//                 child: isResending
//                     ? const CircularProgressIndicator()
//                     : const Text("Resend Email"),
//               ),

//               // ❌ CANCEL
//               TextButton(
//                 onPressed: _cancelAndLogout,
//                 child: const Text(
//                   "Cancel",
//                   style: TextStyle(color: Colors.red),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }