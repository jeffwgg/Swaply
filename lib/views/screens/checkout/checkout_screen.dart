import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/checkout_flow_kind.dart';
import '../../../models/item_listing.dart';
import '../../../models/meetup_address_option.dart';
import '../../../models/payment.dart';
import '../../../models/transaction.dart';
import '../../../repositories/payments_repository.dart';
import '../../../repositories/transactions_repository.dart';
import '../../../services/location_address_service.dart';
import '../../../services/stripe_payment_service.dart';

enum _Fulfillment { meetup, shipping }

enum _UiPaymentMethod { card, grabPay, googlePay }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.flowKind,
    required this.primaryItem,
    required this.sellerDisplayName,
    required this.sellerId,
    required this.buyerId,
    this.swapItem,
    required this.sellerMeetupOptions,
    this.shippingFeeMyr = 10,
  });

  final CheckoutFlowKind flowKind;
  final ItemListing primaryItem;
  final ItemListing? swapItem;
  final String sellerDisplayName;
  final String sellerId;
  final String buyerId;
  final List<MeetupAddressOption> sellerMeetupOptions;
  final double shippingFeeMyr;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String? _selectedMeetupId;
  final TextEditingController _shippingAddressController = TextEditingController();
  final LocationAddressService _locationService = LocationAddressService();
  final StripePaymentService _stripe = StripePaymentService();
  final TransactionsRepository _transactions = TransactionsRepository();
  final PaymentsRepository _payments = PaymentsRepository();

  _UiPaymentMethod _paymentMethod = _UiPaymentMethod.card;
  bool _agreedToTerms = false;
  bool _busy = false;

  late _Fulfillment _fulfillment;

  @override
  void initState() {
    super.initState();
    if (widget.sellerMeetupOptions.isEmpty) {
      _fulfillment = _Fulfillment.shipping;
    } else {
      _fulfillment = _Fulfillment.meetup;
      _selectedMeetupId = widget.sellerMeetupOptions.first.id;
    }
  }

  @override
  void dispose() {
    _shippingAddressController.dispose();
    super.dispose();
  }

  bool get _isSwap => widget.flowKind == CheckoutFlowKind.swap;

  bool get _isShipping => _fulfillment == _Fulfillment.shipping;

  double get _productSubtotal {
    if (_isSwap) {
      return 0;
    }
    return widget.primaryItem.price ?? 0;
  }

  double get _shippingFee => _isShipping ? widget.shippingFeeMyr : 0;

  double get _grandTotal => _productSubtotal + _shippingFee;

  bool get _requiresPayment => _grandTotal > 0.0001;

  bool get _hasMeetupChoices => widget.sellerMeetupOptions.isNotEmpty;

  bool _locationReady() {
    if (_fulfillment == _Fulfillment.meetup) {
      return _hasMeetupChoices && _selectedMeetupId != null;
    }
    return _shippingAddressController.text.trim().isNotEmpty;
  }

  String _formatRm(double value) {
    return 'RM${value.toStringAsFixed(2)}';
  }

  Future<void> _onUseGpsPressed() async {
    setState(() => _busy = true);
    try {
      final line = await _locationService.resolveCurrentAddressLine();
      if (!mounted) {
        return;
      }
      if (line == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read your location. Enable GPS and grant permission, then try again.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _shippingAddressController.text = line;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _onCheckoutPressed() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the transaction instructions.')),
      );
      return;
    }
    if (!_locationReady()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fulfillment == _Fulfillment.meetup
                ? 'Select a meet-up address from the seller.'
                : 'Enter your shipping address.',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      StripePaymentResult? paymentResult;
      if (_requiresPayment) {
        paymentResult = await _stripe.payCheckoutTotal(
          context: context,
          totalMyr: _grandTotal,
          currencyCode: 'myr',
        );
        if (!mounted) {
          return;
        }
        if (!paymentResult.success) {
          if (paymentResult.message != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(paymentResult.message!)),
            );
          }
          return;
        }
      }

      // Create transaction row
      final txType = widget.flowKind == CheckoutFlowKind.swap ? 'trade' : 'purchase';
      final txStatus = _requiresPayment ? 'paid' : 'confirmed';
      final itemPrice = widget.flowKind == CheckoutFlowKind.purchase
          ? widget.primaryItem.price
          : null;
      if (widget.flowKind == CheckoutFlowKind.purchase && itemPrice == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This listing has no price.')),
          );
        }
        return;
      }

      final fulfillment = _fulfillment == _Fulfillment.shipping ? 'shipping' : 'meetup';
      final address = _fulfillment == _Fulfillment.shipping
          ? _shippingAddressController.text.trim()
          : (widget.sellerMeetupOptions
                  .firstWhere((o) => o.id == _selectedMeetupId)
                  .fullAddress);

      Transaction createdTx;
      try {
        createdTx = await _transactions.create(
          Transaction(
            transactionId: 0,
            buyerId: widget.buyerId,
            sellerId: widget.sellerId,
            itemId: widget.primaryItem.id,
            tradedItemId: widget.swapItem?.id,
            transactionType: txType,
            transactionStatus: txStatus,
            itemPrice: itemPrice,
            shippingFee: _shippingFee,
            totalAmount: _grandTotal,
            fulfillmentMethod: fulfillment,
            address: address,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saving transaction failed: $e')),
          );
        }
        return;
      }

      // Create payment row if a real charge happened
      if (_requiresPayment) {
        final intentId = paymentResult?.paymentIntentId;
        if (intentId == null || intentId.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment succeeded but no intent id found.')),
            );
          }
          return;
        }
        final method = switch (_paymentMethod) {
          _UiPaymentMethod.card => 'card',
          _UiPaymentMethod.grabPay => 'grabpay',
          _UiPaymentMethod.googlePay => 'google_pay',
        };
        try {
          await _payments.create(
            Payment(
              paymentId: 0,
              paymentIntentId: intentId,
              paymentMethod: method,
              paymentAmount: _grandTotal,
              paymentStatus: 'paid',
              transactionId: createdTx.transactionId,
              createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            ),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Payment OK, but saving payment failed: $e')),
            );
          }
          return;
        }
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order confirmed.')),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text('Order Request'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B1340),
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FulfillmentToggle(
                    value: _fulfillment,
                    meetupEnabled: widget.sellerMeetupOptions.isNotEmpty,
                    onChanged: (v) => setState(() => _fulfillment = v),
                  ),
                  const SizedBox(height: 12),
                  if (_fulfillment == _Fulfillment.meetup)
                    _MeetupSection(
                      options: widget.sellerMeetupOptions,
                      selectedId: _selectedMeetupId,
                      onSelect: (id) => setState(() => _selectedMeetupId = id),
                    )
                  else
                    _ShippingSection(
                      controller: _shippingAddressController,
                      onChanged: () => setState(() {}),
                      onUseGps: _busy ? null : _onUseGpsPressed,
                    ),
                  const SizedBox(height: 12),
                  _ProductBlock(
                    sellerName: widget.sellerDisplayName,
                    item: widget.primaryItem,
                    caption: _isSwap ? 'Item you are receiving' : null,
                  ),
                  if (_isSwap && widget.swapItem != null) ...[
                    const SizedBox(height: 10),
                    _ProductBlock(
                      sellerName: 'You',
                      item: widget.swapItem!,
                      caption: 'Your swap offer',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _PriceSummaryCard(
                    isSwap: _isSwap,
                    isShipping: _isShipping,
                    productSubtotal: _productSubtotal,
                    shippingFee: _shippingFee,
                    grandTotal: _grandTotal,
                    formatRm: _formatRm,
                  ),
                  if (_requiresPayment) ...[
                    const SizedBox(height: 12),
                    _PaymentMethodsCard(
                      value: _paymentMethod,
                      onChanged: (m) => setState(() => _paymentMethod = m),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    _InfoNote(
                      text: _isSwap
                          ? 'Swap trades do not charge the other item’s price. For meet-up there is no shipping fee, so there is nothing to pay with a card here.'
                          : 'There is nothing to pay online for this checkout total.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreedToTerms,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: Color(0xFF4B4B61),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                                children: [
                                  const TextSpan(text: 'I have read and agreed to '),
                                  TextSpan(
                                    text: 'Second-Hand Transaction Instructions',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
          _BottomBar(
            busy: _busy,
            totalLabel: _formatRm(_grandTotal),
            buttonLabel: _requiresPayment ? 'Check Out' : 'Confirm',
            onPressed: _busy ? null : _onCheckoutPressed,
          ),
        ],
      ),
    );
  }
}

class _FulfillmentToggle extends StatelessWidget {
  const _FulfillmentToggle({
    required this.value,
    required this.meetupEnabled,
    required this.onChanged,
  });

  final _Fulfillment value;
  final bool meetupEnabled;
  final ValueChanged<_Fulfillment> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _Fulfillment mode) {
      final selected = value == mode;
      final canSelectMeetup = meetupEnabled || mode == _Fulfillment.shipping;
      return Expanded(
        child: Material(
          color: selected ? const Color(0xFFE9E1FE) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canSelectMeetup ? () => onChanged(mode) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? AppColors.primaryLight : const Color(0xFFE6E3F5),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: !canSelectMeetup && mode == _Fulfillment.meetup
                      ? const Color(0xFFBDBACE)
                      : selected
                          ? AppColors.primary
                          : const Color(0xFF7A7890),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            chip('Shipping', _Fulfillment.shipping),
            const SizedBox(width: 10),
            chip('Meet-Up', _Fulfillment.meetup),
          ],
        ),
        if (!meetupEnabled) ...[
          const SizedBox(height: 8),
          Text(
            'This seller has not added a meet-up address on the listing. Delivery is shipping only.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ],
    );
  }
}

class _MeetupSection extends StatelessWidget {
  const _MeetupSection({
    required this.options,
    required this.selectedId,
    required this.onSelect,
  });

  final List<MeetupAddressOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Meet-Up Location',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1B1340),
          ),
        ),
        const SizedBox(height: 8),
        if (options.isEmpty)
          _CardShell(
            child: Text(
              'The seller has not added any meet-up addresses yet.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          )
        else
          ...options.map((o) {
            final selected = o.id == selectedId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onSelect(o.id),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? AppColors.primary : const Color(0xFFE6E3F5),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9E1FE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.location_pin, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1B1340),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                o.fullAddress,
                                style: const TextStyle(
                                  color: Color(0xFF5C5A72),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? AppColors.primary
                              : const Color(0xFFC8C6D6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _ShippingSection extends StatelessWidget {
  const _ShippingSection({
    required this.controller,
    required this.onChanged,
    required this.onUseGps,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback? onUseGps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Shipping Address',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1B1340),
          ),
        ),
        const SizedBox(height: 8),
        _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9E1FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.location_pin, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: (_) => onChanged(),
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Add shipping address',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onUseGps,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Use current location (GPS)'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.item});

  final ItemListing item;

  static const double _size = 86;

  @override
  Widget build(BuildContext context) {
    if (item.imageUrls.isEmpty) {
      return Image.asset(
        'assets/sample.jpeg',
        width: _size,
        height: _size,
        fit: BoxFit.cover,
      );
    }
    final url = item.imageUrls.first;
    if (url.startsWith('http')) {
      return Image.network(
        url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, _) => Image.asset(
          'assets/sample.jpeg',
          width: _size,
          height: _size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Image.asset(
      url,
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, _) => Image.asset(
        'assets/sample.jpeg',
        width: _size,
        height: _size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _ProductBlock extends StatelessWidget {
  const _ProductBlock({
    required this.sellerName,
    required this.item,
    this.caption,
  });

  final String sellerName;
  final ItemListing item;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final price = item.price;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption != null) ...[
            Text(
              caption!,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_rounded, color: AppColors.primary, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          sellerName.toUpperCase(),
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B1340),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: const TextStyle(color: Color(0xFF6F6D86), height: 1.3),
                    ),
                    if (price != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'RM${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _ProductThumbnail(item: item),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceSummaryCard extends StatelessWidget {
  const _PriceSummaryCard({
    required this.isSwap,
    required this.isShipping,
    required this.productSubtotal,
    required this.shippingFee,
    required this.grandTotal,
    required this.formatRm,
  });

  final bool isSwap;
  final bool isShipping;
  final double productSubtotal;
  final double shippingFee;
  final double grandTotal;
  final String Function(double) formatRm;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        children: [
          if (!isSwap) ...[
            _MoneyRow(label: 'Subtotal', value: formatRm(productSubtotal)),
            const SizedBox(height: 8),
          ],
          if (isShipping) ...[
            _MoneyRow(label: 'Shipping Fee', value: formatRm(shippingFee)),
            const SizedBox(height: 8),
          ],
          _MoneyRow(label: 'Remarks', value: '-', emphasize: false),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1B1340),
                ),
              ),
              const Spacer(),
              Text(
                formatRm(grandTotal),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1B1340),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.emphasize = true,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize ? const Color(0xFF4B4B61) : const Color(0xFF8A889E),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: emphasize ? const Color(0xFF1B1340) : const Color(0xFF8A889E),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodsCard extends StatelessWidget {
  const _PaymentMethodsCard({
    required this.value,
    required this.onChanged,
  });

  final _UiPaymentMethod value;
  final ValueChanged<_UiPaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget row(String title, _UiPaymentMethod mode) {
      final selected = value == mode;
      return InkWell(
        onTap: () => onChanged(mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1340),
                  ),
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primary : const Color(0xFFC8C6D6),
              ),
            ],
          ),
        ),
      );
    }

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Methods',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B1340),
            ),
          ),
          const Divider(height: 22),
          row('Credit / Debit Card', _UiPaymentMethod.card),
          row('GrabPay', _UiPaymentMethod.grabPay),
          row('Google Pay', _UiPaymentMethod.googlePay),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF5C5A72), height: 1.35),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFECEAF7)),
      ),
      child: child,
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.busy,
    required this.totalLabel,
    required this.buttonLabel,
    required this.onPressed,
  });

  final bool busy;
  final String totalLabel;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Color(0xFF1B1340), fontSize: 14),
                    children: [
                      const TextSpan(text: 'Total '),
                      TextSpan(
                        text: totalLabel,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onPressed,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
