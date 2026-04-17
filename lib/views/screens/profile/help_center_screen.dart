import 'package:flutter/material.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  // FAQ data structure
  final List<Map<String, String>> faqs = [
    {
      'question': 'How do I create an account?',
      'answer':
          'To create an account, tap the "Register" button on the login screen. Enter your email address and create a strong password (at least 6 characters). You\'ll receive a verification email - click the link to verify your account. After verification, complete your profile setup.'
    },
    {
      'question': 'How do I verify my email?',
      'answer':
          'After registration, check your email inbox for a verification link from Swaply. Click the link within 24 hours to verify your email. If you don\'t receive it, tap "Resend Email" on the verification screen. Check your spam folder if you can\'t find it.'
    },
    {
      'question': 'How does the trading process work?',
      'answer':
          'Browse items from other users in the Discover section. Find something you like and message the seller. Negotiate the terms and arrange a meetup. Inspect the item before trading and complete the exchange. Rate each other after the trade is complete.'
    },
    {
      'question': 'How do I create a listing?',
      'answer':
          'Tap the "+" button on the home screen to create a new listing. Add photos of your item, write a clear description, set a trading value, and specify any items you\'d like in exchange. Your listing will appear in the Discover section for other users to browse.'
    },
    {
      'question': 'How do I report an issue with a user?',
      'answer':
          'If you encounter a problematic user, visit their profile and tap the report icon. Select the reason for your report (fraud, inappropriate behavior, etc.) and provide details. Our team reviews all reports and takes appropriate action.'
    },
    {
      'question': 'Can I delete my account?',
      'answer':
          'To delete your account, go to Settings > Account. Contact support and request account deletion. Please note that this action is permanent and cannot be undone. All your listings and trading history will be removed.'
    },
    {
      'question': 'How do I reset my password?',
      'answer':
          'Go to Settings > Change Password. Enter your current password and your new password. You can also use the "Forgot Password" option on the login screen if you don\'t remember your current password.'
    },
    {
      'question': 'Is my personal information safe?',
      'answer':
          'Yes, we take security seriously. Your data is encrypted and stored securely on our servers. We never share your personal information with third parties without your consent. For more details, check our privacy policy.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text("Help Center"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Frequently Asked Questions",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Find answers to common questions about Swaply",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // FAQs using ExpansionTile
              ..._buildFAQTiles(),

              const SizedBox(height: 24),

              // Contact Support Section
              _buildContactSupportSection(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFAQTiles() {
    return faqs.map((faq) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: ExpansionTile(
          title: Text(
            faq['question']!,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          iconColor: Colors.purple,
          collapsedIconColor: Colors.grey,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                faq['answer']!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildContactSupportSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headset_mic,
                  color: Colors.purple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Still need help?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Can't find what you're looking for? Reach out to our support team and we'll be happy to help!",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildContactButton(
                  icon: Icons.mail_outline,
                  label: "Email Support",
                  onTap: () => _showContactInfo("support@swaply.com"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildContactButton(
                  icon: Icons.help_outline,
                  label: "FAQ",
                  onTap: () => _showFAQInfo(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.purple),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.purple),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.purple,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showContactInfo(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Contact Support"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Email us at:"),
            const SizedBox(height: 8),
            SelectableText(
              email,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "We typically respond within 24 hours.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _showFAQInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Additional Resources"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildResourceItem("📖", "Browse our knowledge base"),
            _buildResourceItem("🎥", "Watch tutorial videos"),
            _buildResourceItem("💬", "Join our community forum"),
            _buildResourceItem("📱", "Check app documentation"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
