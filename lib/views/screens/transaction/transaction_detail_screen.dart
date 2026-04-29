import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../../../core/utils/app_snack_bars.dart';
import '../../../models/app_user.dart';
import '../../../models/item_listing.dart';
import '../../../models/payment.dart';
import '../../../models/transaction.dart';
import '../../../repositories/items_repository.dart';
import '../../../repositories/payments_repository.dart';
import '../../../repositories/transactions_repository.dart';
import '../../../repositories/local/local_transactions_repository.dart';
import '../../../repositories/users_repository.dart';
import '../../../services/supabase_service.dart';
import '../profile/profile_screen.dart';
import 'qr_scan_screen.dart';
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionDetailScreen extends StatefulWidget {
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

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final TransactionsRepository _txRepo = TransactionsRepository();
  final ItemsRepository _itemsRepo = ItemsRepository();
  final UsersRepository _usersRepo = UsersRepository();

  late Future<_TxDetailData> _future;
  RealtimeChannel? _realtimeChannel;
  DateTime _lastRealtimeReloadAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _future = _load();
    _startRealtime();
  }

  @override
  void dispose() {
    _stopRealtime();
    super.dispose();
  }

  void _startRealtime() {
    _stopRealtime();

    final txId = widget.tx.transactionId;
    final channel = SupabaseService.client.channel('tx_detail:$txId');

    // Reload helper with light throttling (multiple rows may update quickly).
    void scheduleReload() {
      final now = DateTime.now();
      if (now.difference(_lastRealtimeReloadAt).inMilliseconds < 800) return;
      _lastRealtimeReloadAt = now;
      if (mounted) _reload();
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'transactions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'transaction_id',
        value: txId,
      ),
      callback: (_) => scheduleReload(),
    );

    // Primary item updates
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'items',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: widget.tx.itemId,
      ),
      callback: (_) => scheduleReload(),
    );

    // Traded item updates (if any)
    if (widget.tx.tradedItemId != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'items',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: widget.tx.tradedItemId!,
        ),
        callback: (_) => scheduleReload(),
      );
    }

    channel.subscribe();
    _realtimeChannel = channel;
  }

  void _stopRealtime() {
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null) {
      SupabaseService.client.removeChannel(channel);
    }
  }

  Future<_TxDetailData> _load() async {
    try {
      final latestTx =
          await _txRepo.getById(widget.tx.transactionId) ?? widget.tx;
      final item = await _itemsRepo.getById(latestTx.itemId);
      final traded = latestTx.tradedItemId == null
          ? null
          : await _itemsRepo.getById(latestTx.tradedItemId!);
      final buyerUser = await _usersRepo.getById(latestTx.buyerId);
      return _TxDetailData(
        tx: latestTx,
        item: item ?? widget.item,
        tradedItem: traded ?? widget.tradedItem,
        buyerUser: buyerUser,
      );
    } catch (_) {
      final cached = await LocalTransactionsRepository()
          .getById(widget.tx.transactionId);
      if (cached == null) {
        return _TxDetailData(
          tx: widget.tx,
          item: widget.item,
          tradedItem: widget.tradedItem,
          buyerUser: null,
        );
      }

      final offlineItem = widget.item ??
          ItemListing(
            id: cached.tx.itemId,
            name: cached.itemName ?? 'Item #${cached.tx.itemId}',
            description: '',
            price: cached.tx.itemPrice,
            listingType: 'sell',
            ownerId: cached.tx.sellerId,
            status: cached.itemStatus ?? 'unknown',
            category: cached.itemCategory ?? '',
            imageUrls:
                cached.itemImageUrl == null ? [] : [cached.itemImageUrl!],
            preference: null,
            repliedTo: null,
            createdAt: cached.tx.createdAt,
            address: null,
            latitude: null,
            longitude: null,
          );

      final offlineTraded = cached.tx.tradedItemId == null
          ? widget.tradedItem
          : (widget.tradedItem ??
              ItemListing(
                id: cached.tx.tradedItemId ?? 0,
                name:
                    cached.tradedItemName ?? 'Item #${cached.tx.tradedItemId}',
                description: '',
                price: null,
                listingType: 'trade',
                ownerId: cached.tx.buyerId,
                status: cached.tradedItemStatus ?? 'unknown',
                category: cached.tradedItemCategory ?? '',
                imageUrls: cached.tradedItemImageUrl == null
                    ? []
                    : [cached.tradedItemImageUrl!],
                preference: null,
                repliedTo: null,
                createdAt: cached.tx.createdAt,
                address: null,
                latitude: null,
                longitude: null,
              ));

      return _TxDetailData(
        tx: cached.tx,
        item: offlineItem,
        tradedItem: offlineTraded,
        buyerUser: null,
      );
    }
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  String _formatRm(double value) => 'RM ${value.toStringAsFixed(2)}';

  Future<void> _confirmReceived({
    required BuildContext context,
    required Transaction tx,
  }) async {
    final isTrade = tx.tradedItemId != null;
    final viewerIsBuyer = widget.isBuyer;
    final viewerIsSeller = !viewerIsBuyer;
    final roleLabel = viewerIsBuyer ? 'buyer' : (viewerIsSeller ? 'seller' : 'user');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm received'),
        content: Text(
          isTrade
              ? 'As the $roleLabel, confirm you have met up and received the item? '
                  'This will mark your counterparty’s item as completed.'
              : 'Confirm you have completed this transaction?',
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

    try {
      if (isTrade) {
        // Buyer confirms seller's item. Seller confirms buyer's offered item.
        if (viewerIsBuyer) {
          await _itemsRepo.updateStatus('completed', tx.itemId);
        } else if (viewerIsSeller && tx.tradedItemId != null) {
          await _itemsRepo.updateStatus('completed', tx.tradedItemId!);
        }
      } else {
        // Purchase: either party can mark as completed for the single item.
        await _itemsRepo.updateStatus('completed', tx.itemId);
      }

      // Only mark transaction completed when BOTH items are completed (trade),
      // or the single item is completed (purchase).
      final primary = await _itemsRepo.getById(tx.itemId);
      final traded = tx.tradedItemId == null
          ? null
          : await _itemsRepo.getById(tx.tradedItemId!);
      final primaryDone = primary?.status == 'completed';
      final tradedDone = tx.tradedItemId == null ? true : (traded?.status == 'completed');

      if (primaryDone && tradedDone) {
        await _txRepo.updateStatus(
          transactionId: tx.transactionId,
          transactionStatus: 'completed',
        );
      }

      widget.onChanged();
      if (!context.mounted) return;
      AppSnackBars.success(
        context,
        (primaryDone && tradedDone)
            ? 'Transaction completed.'
            : 'Marked as received. Waiting for the other party.',
      );
      _reload();
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBars.error(context, 'Failed to mark received: $e');
    }
  }

  Future<void> _showMyTradeQr({
    required BuildContext context,
    required Transaction tx,
  }) async {
    final role = widget.isBuyer ? 'buyer' : 'seller';
    final payload = TradeQrPayload(
      transactionId: tx.transactionId,
      role: role,
      uid: widget.viewer.id,
    );
    final raw = jsonEncode(payload.toJson());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your meet-up QR',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                  color: const Color(0xFFF8F5FF),
                ),
                child: QrImageView(
                  data: raw,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Let the other party scan this QR.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _scanTradeQrAndConfirm(context: context, tx: tx);
                      },
                      child: const Text('Scan QR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanTradeQrAndConfirm({
    required BuildContext context,
    required Transaction tx,
  }) async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(title: 'Scan meet-up QR'),
      ),
    );
    if (!mounted || raw == null || raw.trim().isEmpty) return;

    final parsed = TradeQrPayload.tryParse(raw.trim());
    if (parsed == null) {
      if (!context.mounted) return;
      AppSnackBars.error(context, 'Invalid QR code.');
      return;
    }

    if (parsed.transactionId != tx.transactionId) {
      if (!context.mounted) return;
      AppSnackBars.error(context, 'This QR is for a different transaction.');
      return;
    }

    final myRole = widget.isBuyer ? 'buyer' : 'seller';
    if (parsed.role == myRole) {
      if (!context.mounted) return;
      AppSnackBars.error(context, 'You cannot scan your own QR.');
      return;
    }

    // Must match the counterparty identity for this transaction.
    final expectedCounterpartyUid =
        myRole == 'buyer' ? tx.sellerId : tx.buyerId;
    final expectedCounterpartyRole =
        myRole == 'buyer' ? 'seller' : 'buyer';
    if (parsed.uid != expectedCounterpartyUid ||
        parsed.role != expectedCounterpartyRole) {
      if (!context.mounted) return;
      AppSnackBars.error(context, 'This QR does not belong to your counterparty.');
      return;
    }

    // Success: scanning partner QR counts as "Received" confirmation.
    await _confirmReceived(context: context, tx: tx);
  }

  Future<void> _confirmCancel({
    required BuildContext context,
    required Transaction tx,
    required Payment? payment,
  }) async {
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

    final paymentsRepo = PaymentsRepository();
    try {
      await _itemsRepo.updateStatus('available', tx.itemId);
      if (tx.tradedItemId != null) {
        final viewerIsBuyer = widget.isBuyer;
        // Offerer (buyer) cancel => drop offered item; seller cancel => available.
        await _itemsRepo.updateStatus(
          viewerIsBuyer ? 'dropped' : 'rejected',
          tx.tradedItemId!,
        );
      }
      await _txRepo.updateStatus(
        transactionId: tx.transactionId,
        transactionStatus: 'cancelled',
        cancelledBy: widget.isBuyer ? 'buyer' : 'seller',
      );
      if (payment != null) {
        await paymentsRepo.updateStatusForTransaction(
          transactionId: tx.transactionId,
          paymentStatus: 'refunded',
        );
      }

      widget.onChanged();
      if (!context.mounted) return;
      AppSnackBars.info(context, 'Cancelled. Refund will be issued in 3 working days.');
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBars.error(context, 'Failed to cancel: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text('Transaction Details'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B1340),
        surfaceTintColor: Colors.transparent,
      ),
      body: FutureBuilder<_TxDetailData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final tx = data?.tx ?? widget.tx;
          final item = data?.item ?? widget.item;
          final tradedItem = data?.tradedItem ?? widget.tradedItem;
          final buyerUser = data?.buyerUser;

          final title = item?.name ?? 'Item #${tx.itemId}';
          final image = (item != null && item.imageUrls.isNotEmpty)
              ? item.imageUrls.first
              : null;
          final status = tx.transactionStatus ?? 'pending';
          final amount = tx.totalAmount ?? tx.itemPrice ?? 0;
          final dateLabel =
              DateFormat('MMM d, yyyy • hh:mm a').format(tx.createdAt.toLocal());
          final isTrade = tx.tradedItemId != null;

          final viewerIsParticipant =
              widget.viewer.id == tx.buyerId || widget.viewer.id == tx.sellerId;

          // Rely on the `isBuyer` flag passed by the caller. This keeps the
          // button enable/disable behavior aligned with the navigation context.
          final viewerIsBuyer = widget.isBuyer;

          // Trade receipt state:
          // - buyer confirms seller's item => tx.itemId => buyerReceived == true
          // - seller confirms buyer's offered item => tx.tradedItemId => sellerReceived == true
          final buyerReceived = item?.status == 'completed';
          final sellerReceived = tradedItem?.status == 'completed';

          // Disable rules (trade):
          // - "Scan QR" should disable when the viewer has already received the counterparty's item.
          // - "Generate QR Code" should disable when the counterparty has already received the viewer's item.
          final viewerAlreadyReceivedOtherPartyItem =
              viewerIsBuyer ? buyerReceived : sellerReceived;
          final viewerAlreadyReceivedMyItem =
              viewerIsBuyer ? sellerReceived : buyerReceived;

          // Purchase "Received" action:
          final canDoPurchaseReceivedAction =
              viewerIsParticipant && status == 'pending' && item?.status != 'completed';
          final isMeetupPurchase =
              !isTrade && (tx.fulfillmentMethod ?? '').toLowerCase() == 'meetup';
          final showCancel = status == 'pending';

          String? cancelledByLabel;
          if (status == 'cancelled') {
            final raw = (tx.cancelledBy ?? '').trim().toLowerCase();
            if (raw == 'buyer' || raw == 'seller') {
              cancelledByLabel = raw;
            } else if (isTrade) {
              // Fallback for older rows: infer from traded item status.
              // buyer-cancel => offered item dropped; seller-cancel => offered item rejected
              final offeredStatus = tradedItem?.status?.toLowerCase();
              if (offeredStatus == 'dropped') cancelledByLabel = 'buyer';
              if (offeredStatus == 'rejected') cancelledByLabel = 'seller';
            }
          }

          return SingleChildScrollView(
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
                          if (cancelledByLabel != null) ...[
                            const SizedBox(height: 4),
                            Text('Cancelled by: $cancelledByLabel'),
                          ],
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
                          if (cancelledByLabel != null) ...[
                            const SizedBox(height: 4),
                            Text('Cancelled by: $cancelledByLabel'),
                          ],
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
                leftItem: viewerIsBuyer ? item : tradedItem,
                rightTitle: 'Item you will give',
                rightItem: viewerIsBuyer ? tradedItem : item,
              ),
              const SizedBox(height: 12),
            ],
            if (isTrade) ...[
              _ReceivedStatusCard(
                buyerReceived: buyerReceived,
                sellerReceived: sellerReceived,
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
                  Text(
                    viewerIsBuyer ? 'Seller' : 'Buyer',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            viewingUserId:
                                viewerIsBuyer ? tx.sellerId : tx.buyerId,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      viewerIsBuyer
                          ? (widget.seller?.username ?? tx.sellerId)
                          : (buyerUser?.username ?? tx.buyerId),
                      style: const TextStyle(
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
                  Text(
                    (tx.fulfillmentMethod ?? '').toLowerCase() == 'shipping'
                        ? 'Shipping address'
                        : 'Meet-up location',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
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
                  if (widget.payment == null)
                    const Text('No payment record.')
                  else ...[
                    Text('Method: ${widget.payment!.paymentMethod}'),
                    Text('Status: ${widget.payment!.paymentStatus}'),
                    Text('Amount: ${_formatRm(widget.payment!.paymentAmount)}'),
                  ],
                ],
              ),
            ),
            if (status == 'cancelled' && !isTrade && widget.payment != null) ...[
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
            if (isTrade && viewerIsParticipant && status == 'confirmed') ...[
              FilledButton(
                onPressed: viewerAlreadyReceivedMyItem
                    ? null
                    : () => _showMyTradeQr(context: context, tx: tx),
                child: const Text('Generate QR Code'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: viewerAlreadyReceivedOtherPartyItem
                    ? null
                    : () => _scanTradeQrAndConfirm(context: context, tx: tx),
                child: const Text('Scan QR'),
              ),
            ] else if (!isTrade && isMeetupPurchase && canDoPurchaseReceivedAction) ...[
              // Purchase meetup QR flow:
              // - seller: generate QR
              // - buyer: scan QR (one-way, since there is only one item)
              if (viewerIsBuyer) ...[
                FilledButton(
                  onPressed: () => _scanTradeQrAndConfirm(context: context, tx: tx),
                  child: const Text('Scan QR'),
                ),
              ] else ...[
                FilledButton(
                  onPressed: () => _showMyTradeQr(context: context, tx: tx),
                  child: const Text('Generate QR Code'),
                ),
              ],
            ] else if (!isTrade && canDoPurchaseReceivedAction && !isMeetupPurchase) ...[
              FilledButton(
                onPressed: () => _confirmReceived(context: context, tx: tx),
                child: const Text('Received'),
              ),
            ],
            if (showCancel) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => _confirmCancel(
                  context: context,
                  tx: tx,
                  payment: widget.payment,
                ),
                child: const Text('Cancel'),
              ),
            ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TxDetailData {
  final Transaction tx;
  final ItemListing? item;
  final ItemListing? tradedItem;
  final AppUser? buyerUser;

  const _TxDetailData({
    required this.tx,
    required this.item,
    required this.tradedItem,
    required this.buyerUser,
  });
}

class _ReceivedStatusCard extends StatelessWidget {
  const _ReceivedStatusCard({
    required this.buyerReceived,
    required this.sellerReceived,
  });

  final bool buyerReceived;
  final bool sellerReceived;

  Widget _row(String label, bool done) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          done ? 'Received' : 'Pending',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: done ? const Color(0xFF16A34A) : const Color(0xFF64748B),
          ),
        ),
      ],
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
            'Meet-up confirmation',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _row('Buyer received', buyerReceived),
          const SizedBox(height: 10),
          _row('Seller received', sellerReceived),
        ],
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
      return Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Colors.grey),
      );
    }
    if (url!.startsWith('http')) {
      return Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey[200],
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }
    if (url!.startsWith('assets/')) {
      return Image.asset(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey[200],
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }
    return Image.file(
      File(url!),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: Colors.grey),
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

