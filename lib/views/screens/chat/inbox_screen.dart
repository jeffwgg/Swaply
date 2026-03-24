import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class InboxScreen extends StatefulWidget {
  final ValueChanged<bool>? onConversationViewChanged;

  const InboxScreen({super.key, this.onConversationViewChanged});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  int _selectedFilter = 0;
  int _selectedConversation = 0;
  bool _showMobileChat = false;

  static const _filters = ['All', 'Buying', 'Selling'];

  final List<_Conversation> _conversations = [
    _Conversation(
      name: 'Alex Rivera',
      status: 'Online',
      badge: 'OFFER SENT',
      timeAgo: '2m ago',
      preview: 'Is the vintage camera still available? I can pick it up today.',
      avatarColors: [Color(0xFFFFD9B1), Color(0xFFB5E2DE)],
      item: _ItemPreview(
        icon: Icons.camera_alt_rounded,
        colors: [Color(0xFF7A4A2C), Color(0xFFB68B61)],
      ),
      messages: [
        _Message(
          text:
              "Hi! Is the vintage camera still available? I'm very interested in picking it up today.",
          time: '09:41 AM',
          isMine: false,
        ),
        _Message(
          text:
              "Hey Alex! Yes, it's still available. I have a few other people asking but since you can come today, I can hold it for you.",
          time: '09:43 AM',
          isMine: true,
        ),
        _Message(
          text:
              "I've sent an offer for \$110. I can meet you at the central park entrance. Does that work?",
          time: '09:45 AM',
          isMine: false,
        ),
      ],
      offer: const _OfferCardData(
        title: 'CURRENT OFFER',
        amount: '\$110.00',
        status: 'Waiting for your response',
      ),
    ),
    _Conversation(
      name: 'Sarah Jenkins',
      status: 'Last seen 3m ago',
      badge: 'TRADE PROPOSED',
      timeAgo: '15m ago',
      preview: 'I can swap my leather jacket for it and top up with cash.',
      avatarColors: [Color(0xFFD9A06C), Color(0xFFF8E3D0)],
      item: _ItemPreview(
        icon: Icons.checkroom_rounded,
        colors: [Color(0xFFEDEFF7), Color(0xFFCCD3E5)],
      ),
      messages: [
        _Message(
          text: 'I can swap my leather jacket for it and top up with cash.',
          time: '11:12 AM',
          isMine: false,
        ),
        _Message(
          text: 'Send me a photo of the jacket and your offer details.',
          time: '11:16 AM',
          isMine: true,
        ),
      ],
      offer: const _OfferCardData(
        title: 'TRADE PROPOSAL',
        amount: 'Jacket + \$25',
        status: 'Awaiting item photos',
      ),
    ),
    _Conversation(
      name: 'Marcus Wu',
      status: 'Active 1h ago',
      badge: 'ORDER PLACED',
      timeAgo: '1h ago',
      preview: "Thanks! I'll send the tracking number once it ships.",
      avatarColors: [Color(0xFF6D8B90), Color(0xFFD2E0E2)],
      item: _ItemPreview(
        icon: Icons.watch_outlined,
        colors: [Color(0xFFFDFDFD), Color(0xFFE6E6E6)],
      ),
      messages: [
        _Message(
          text: "Thanks! I'll send the tracking number once it ships.",
          time: '08:10 AM',
          isMine: false,
        ),
      ],
    ),
    _Conversation(
      name: 'SWAPAI',
      status: 'Assistant',
      badge: null,
      timeAgo: '4h ago',
      preview: 'Hi, how can I help you today?',
      avatarColors: [Color(0xFFF1F1F6), Color(0xFFFFFFFF)],
      item: null,
      messages: [
        _Message(
          text: 'Hi, how can I help you today?',
          time: '07:30 AM',
          isMine: false,
        ),
      ],
      accentNameColor: Color(0xFFFF1E26),
    ),
  ];

  void _setMobileConversationView(bool isOpen) {
    if (_showMobileChat == isOpen) {
      return;
    }

    setState(() => _showMobileChat = isOpen);
    widget.onConversationViewChanged?.call(isOpen);
  }

  void _syncShellChrome(bool isWide) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onConversationViewChanged?.call(!isWide && _showMobileChat);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4FF),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 950;
            final selected = _conversations[_selectedConversation];
            _syncShellChrome(isWide);

            if (isWide) {
              return Row(
                children: [
                  SizedBox(
                    width: 430,
                    child: _InboxPanel(
                      conversations: _conversations,
                      filters: _filters,
                      selectedFilter: _selectedFilter,
                      selectedIndex: _selectedConversation,
                      onFilterSelected: (index) {
                        setState(() => _selectedFilter = index);
                      },
                      onConversationSelected: (index) {
                        setState(() => _selectedConversation = index);
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFFE7DFFF)),
                  Expanded(
                    child: _ChatPanel(conversation: selected, onBack: null),
                  ),
                ],
              );
            }

            if (_showMobileChat) {
              return _ChatPanel(
                conversation: selected,
                onBack: () => _setMobileConversationView(false),
              );
            }

            return _InboxPanel(
              conversations: _conversations,
              filters: _filters,
              selectedFilter: _selectedFilter,
              selectedIndex: _selectedConversation,
              onFilterSelected: (index) {
                setState(() => _selectedFilter = index);
              },
              onConversationSelected: (index) {
                setState(() {
                  _selectedConversation = index;
                });
                _setMobileConversationView(true);
              },
            );
          },
        ),
      ),
    );
  }
}

class _InboxPanel extends StatelessWidget {
  final List<_Conversation> conversations;
  final List<String> filters;
  final int selectedFilter;
  final int selectedIndex;
  final ValueChanged<int> onFilterSelected;
  final ValueChanged<int> onConversationSelected;

  const _InboxPanel({
    required this.conversations,
    required this.filters,
    required this.selectedFilter,
    required this.selectedIndex,
    required this.onFilterSelected,
    required this.onConversationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF3F0FF)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                _HeaderIconButton(
                  icon: Icons.menu_rounded,
                  onTap: () {},
                  compact: true,
                ),
                const Expanded(
                  child: Text(
                    'Inbox',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF1A2340),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: () {},
                  filled: true,
                ),
                const SizedBox(width: 10),
                _HeaderIconButton(
                  icon: Icons.search_rounded,
                  onTap: () {},
                  compact: true,
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE8E1FF)),
          SizedBox(
            height: 68,
            child: Row(
              children: List.generate(filters.length, (index) {
                final isActive = selectedFilter == index;
                return GestureDetector(
                  onTap: () => onFilterSelected(index),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isActive
                              ? const Color(0xFF7A54FF)
                              : Colors.transparent,
                          width: 4,
                        ),
                      ),
                    ),
                    child: Text(
                      filters[index],
                      style: TextStyle(
                        color: isActive
                            ? const Color(0xFF7A54FF)
                            : const Color(0xFF98A2B7),
                        fontSize: 18,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 120),
              itemCount: conversations.length,
              separatorBuilder: (_, index) =>
                  Container(height: 1, color: const Color(0xFFE8E1FF)),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return InkWell(
                  onTap: () => onConversationSelected(index),
                  child: Container(
                    color: index == selectedIndex
                        ? const Color(0xFFF7F3FF)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AvatarBubble(
                          name: conversation.name,
                          colors: conversation.avatarColors,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conversation.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            conversation.accentNameColor ??
                                            const Color(0xFF19213C),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    conversation.timeAgo,
                                    style: const TextStyle(
                                      color: Color(0xFFA6B0C7),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (conversation.badge != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1EBFF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFD8CBFF),
                                    ),
                                  ),
                                  child: Text(
                                    conversation.badge!,
                                    style: const TextStyle(
                                      color: Color(0xFF6E4CFF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Text(
                                conversation.preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF53627E),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          children: [
                            if (conversation.item != null)
                              _ItemThumb(item: conversation.item!),
                            if (index == 0) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7A54FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 30, bottom: 84),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9A6BFF), Color(0xFF6E35F6)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7E57FF).withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  final _Conversation conversation;
  final VoidCallback? onBack;

  const _ChatPanel({required this.conversation, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F2FF)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                if (onBack != null) ...[
                  _HeaderIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: onBack!,
                    compact: true,
                  ),
                  const SizedBox(width: 6),
                ],
                _AvatarBubble(
                  name: conversation.name,
                  colors: conversation.avatarColors,
                  size: 54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.name,
                        style: const TextStyle(
                          color: Color(0xFF1A2340),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFF32C965),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            conversation.status,
                            style: const TextStyle(
                              color: Color(0xFF925AFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (conversation.item != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE6D9FF)),
                    ),
                    child: _ItemThumb(item: conversation.item!, size: 48),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE7DFFF)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                children: [
                  const Text(
                    'TODAY',
                    style: TextStyle(
                      color: Color(0xFFC18EFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  ...conversation.messages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final message = entry.value;
                    final showOffer = conversation.offer != null && index == 1;
                    return Column(
                      children: [
                        _MessageBubble(message: message),
                        if (showOffer) ...[
                          const SizedBox(height: 18),
                          _OfferCard(offer: conversation.offer!),
                          const SizedBox(height: 18),
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          Container(height: 1, color: const Color(0xFFE7DFFF)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: const [
                      _ActionChip(
                        icon: Icons.place_outlined,
                        label: 'Send Location',
                        highlighted: false,
                      ),
                      SizedBox(width: 12),
                      _ActionChip(
                        icon: Icons.compare_arrows_rounded,
                        label: 'Propose Trade',
                        highlighted: true,
                      ),
                      SizedBox(width: 12),
                      _ActionChip(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Make Payment',
                        highlighted: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFDCCFFF)),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFFB58DFF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFF),
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(color: const Color(0xFFE4EAF5)),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Type a message...',
                                style: TextStyle(
                                  color: Color(0xFF9AABCA),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.sentiment_satisfied_alt_outlined,
                              color: Color(0xFF90A1C3),
                              size: 30,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF935FFF), Color(0xFF6D2DF5)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF7E57FF,
                            ).withValues(alpha: 0.34),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 29,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _Message message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: message.isMine ? null : Colors.white,
        gradient: message.isMine
            ? const LinearGradient(
                colors: [Color(0xFF9B68FF), Color(0xFF7D41FF)],
              )
            : null,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF161A2B).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        message.text,
        style: TextStyle(
          color: message.isMine ? Colors.white : const Color(0xFF24314D),
          fontSize: 16,
          height: 1.6,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: message.isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          bubble,
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              message.time,
              style: const TextStyle(
                color: Color(0xFFA5B0C7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final _OfferCardData offer;

  const _OfferCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDECFFF), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E57FF).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                Text(
                  offer.title,
                  style: const TextStyle(
                    color: Color(0xFF6F45FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.handshake_outlined,
                  color: Color(0xFF7A54FF),
                  size: 22,
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE9DCFF)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Offer Amount',
                        style: TextStyle(
                          color: Color(0xFF7F8CA7),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        offer.amount,
                        style: const TextStyle(
                          color: Color(0xFF18213C),
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                const _OfferButton(
                  label: 'Decline',
                  foreground: Color(0xFF42526E),
                  background: Color(0xFFF0F3F8),
                ),
                const SizedBox(width: 10),
                const _OfferButton(
                  label: 'Accept',
                  foreground: Colors.white,
                  background: Color(0xFF793BFF),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF97A5C1),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  offer.status,
                  style: const TextStyle(
                    color: Color(0xFF97A5C1),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferButton extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;

  const _OfferButton({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFEAF0FF) : const Color(0xFFF9F4FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? const Color(0xFFD7E3FF)
              : const Color(0xFFEAD9FF),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: highlighted ? const Color(0xFF4E5FE3) : AppColors.navActive,
            size: 19,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: highlighted
                  ? const Color(0xFF4E5FE3)
                  : AppColors.navActive,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool compact;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: compact ? 44 : 56,
        height: compact ? 44 : 56,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFF1E9FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: const Color(0xFF7A54FF), size: 30),
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  final String name;
  final List<Color> colors;
  final double size;

  const _AvatarBubble({
    required this.name,
    required this.colors,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final parts = name.split(' ');
    final initials = parts.length > 1
        ? '${parts.first[0]}${parts.last[0]}'
        : name.substring(0, 1);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: const Color(0xFFE6DDFF), width: 2),
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFF1B2543),
            fontSize: size * 0.3,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  final _ItemPreview item;
  final double size;

  const _ItemThumb({required this.item, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: item.colors,
        ),
        border: Border.all(color: const Color(0xFFE7E2F5)),
      ),
      child: Icon(item.icon, color: Colors.white, size: size * 0.52),
    );
  }
}

class _Conversation {
  final String name;
  final String status;
  final String? badge;
  final String timeAgo;
  final String preview;
  final List<Color> avatarColors;
  final _ItemPreview? item;
  final List<_Message> messages;
  final _OfferCardData? offer;
  final Color? accentNameColor;

  const _Conversation({
    required this.name,
    required this.status,
    required this.badge,
    required this.timeAgo,
    required this.preview,
    required this.avatarColors,
    required this.item,
    required this.messages,
    this.offer,
    this.accentNameColor,
  });
}

class _ItemPreview {
  final IconData icon;
  final List<Color> colors;

  const _ItemPreview({required this.icon, required this.colors});
}

class _Message {
  final String text;
  final String time;
  final bool isMine;

  const _Message({
    required this.text,
    required this.time,
    required this.isMine,
  });
}

class _OfferCardData {
  final String title;
  final String amount;
  final String status;

  const _OfferCardData({
    required this.title,
    required this.amount,
    required this.status,
  });
}
