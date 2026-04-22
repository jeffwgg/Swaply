import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/app_user.dart';
import '../../../models/item_listing.dart';
import '../../../models/payment.dart';
import '../../../models/transaction.dart';
import '../../../repositories/items_repository.dart';
import '../../../repositories/payments_repository.dart';
import '../../../repositories/transactions_repository.dart';

class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({
    super.key,
    required this.viewer,
    required this.tx,
    required this.item,
    required this.tradedItem,
    required this.seller,
    required this.payment,
    required this.isBuyer,
    required this.onChanged,
  });

  final AppUser viewer;
  final Transaction tx;
  final ItemListing? item;
  final ItemListing? tradedItem;
  final AppUser? seller;
  final Payment? payment;
  final bool isBuyer;
  final VoidCallback onChanged;

  String _formatRm(double value) => 'RM ${value.toStringAsFixed(2)}';

  Future<void> _confirmReceived(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm received'),
        content: const Text(
          'Confirm you have received the product? This will complete the transaction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final itemsRepo = ItemsRepository();
    final txRepo = TransactionsRepository();
    try {
      await itemsRepo.updateStatus('completed', tx.itemId);
      if (tx.tradedItemId != null) {
        await itemsRepo.updateStatus('completed', tx.tradedItemId!);
      }
      await txRepo.updateStatus(
        transactionId: tx.transactionId,
        transactionStatus: 'completed',
      );
      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as received.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark received: $e')),
      );
    }
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel transaction'),
        content: const Text('Cancel this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel transaction'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final itemsRepo = ItemsRepository();
    final txRepo = TransactionsRepository();
    final paymentsRepo = PaymentsRepository();
    try {
      await itemsRepo.updateStatus('available', tx.itemId);
      if (tx.tradedItemId != null) {
        await itemsRepo.updateStatus('available', tx.tradedItemId!);
      }
      await txRepo.updateStatus(
        transactionId: tx.transactionId,
        transactionStatus: 'cancelled',
      );
      if (payment != null) {
        await paymentsRepo.updateStatusForTransaction(
          transactionId: tx.transactionId,
          paymentStatus: 'refunded',
        );
      }

      onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cancelled. Refund will be issued in 3 working days.'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = item?.name ?? 'Item #${tx.itemId}';
    final image = (item != null && item!.imageUrls.isNotEmpty)
        ? item!.imageUrls.first
        : null;
    final status = tx.transactionStatus ?? 'pending';
    final amount = tx.totalAmount ?? tx.itemPrice ?? 0;
    final dateLabel = DateFormat('MMM d, yyyy • hh:mm a').format(tx.createdAt.toLocal());
    final isTrade = tx.tradedItemId != null;
    final showReceived = isBuyer && (isTrade ? status == 'confirmed' : status == 'pending');
    final showCancel = status == 'pending';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text('Transaction Details'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B1340),
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isTrade) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _Thumb(url: image),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dateLabel,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Text('Status: $status'),
                        ],
                      ),
                    ),
                    Text(
                      _formatRm(amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF5B21B6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trade transaction',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dateLabel,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Text('Status: $status'),
                        ],
                      ),
                    ),
                    Text(
                      _formatRm(amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF5B21B6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (isTrade) ...[
              _TradeItemsCard(
                leftTitle: 'Item you will receive',
                leftItem: item,
                rightTitle: 'Item you will give',
                rightItem: tradedItem,
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seller',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(seller?.username ?? tx.sellerId),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fulfillment',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(tx.fulfillmentMethod ?? '-'),
                  const SizedBox(height: 10),
                  const Text(
                    'Meet-up location',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(tx.address ?? '-'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  if (payment == null)
                    const Text('No payment record.')
                  else ...[
                    Text('Method: ${payment!.paymentMethod}'),
                    Text('Status: ${payment!.paymentStatus}'),
                    Text('Amount: ${_formatRm(payment!.paymentAmount)}'),
                  ],
                ],
              ),
            ),
            if (status == 'cancelled') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4F4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFC7C7)),
                ),
                child: const Text(
                  'Refund will be issued in 3 working days.',
                  style: TextStyle(color: Color(0xFF8A1F1F)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (showReceived)
              FilledButton(
                onPressed: () => _confirmReceived(context),
                child: const Text('Received'),
              ),
            if (showCancel) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => _confirmCancel(context),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    if (url == null || url!.isEmpty) {
      return Image.asset(
        'assets/sample.jpeg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (url!.startsWith('http')) {
      return Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/sample.jpeg',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Image.asset(
      url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/sample.jpeg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _TradeItemsCard extends StatelessWidget {
  const _TradeItemsCard({
    required this.leftTitle,
    required this.leftItem,
    required this.rightTitle,
    required this.rightItem,
  });

  final String leftTitle;
  final ItemListing? leftItem;
  final String rightTitle;
  final ItemListing? rightItem;

  Widget _itemBlock(String title, ItemListing? item) {
    final img = (item != null && item.imageUrls.isNotEmpty) ? item.imageUrls.first : null;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F5FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE9D5FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 110,
                width: double.infinity,
                child: _Thumb(url: img),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item?.name ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              item?.category ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9D5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trade items',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _itemBlock(leftTitle, leftItem),
              const SizedBox(width: 12),
              _itemBlock(rightTitle, rightItem),
            ],
          ),
        ],
      ),
    );
  }
}

