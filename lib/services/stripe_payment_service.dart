import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';

class StripePaymentResult {
  final bool success;
  final String? message;

  const StripePaymentResult({required this.success, this.message});
}

/// Handles Stripe PaymentSheet when a backend URL is configured, otherwise
/// shows a small in-app simulator suitable for coursework demos.
class StripePaymentService {
  StripePaymentService();

  static Future<void> ensureStripeConfigured() async {
    if (!AppConfig.hasStripePublishableKey) {
      return;
    }
    Stripe.publishableKey = AppConfig.stripePublishableKey.trim();
    await Stripe.instance.applySettings();
  }

  Future<StripePaymentResult> payCheckoutTotal({
    required BuildContext context,
    required double totalMyr,
    required String currencyCode,
  }) async {
    final minor = _myrToMinorUnits(totalMyr);
    if (minor <= 0) {
      return const StripePaymentResult(success: true);
    }

    if (!AppConfig.hasStripePublishableKey ||
        !AppConfig.hasStripePaymentIntentEndpoint) {
      return _simulate(context, totalMyr);
    }

    try {
      final clientSecret = await _fetchClientSecret(
        amountMinorUnits: minor,
        currencyCode: currencyCode,
      );
      if (clientSecret == null || clientSecret.isEmpty) {
        return const StripePaymentResult(
          success: false,
          message: 'Could not start payment.',
        );
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Swaply',
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return const StripePaymentResult(success: true);
    } on StripeException catch (e) {
      final canceled = e.error.code == FailureCode.Canceled;
      if (canceled) {
        return const StripePaymentResult(
          success: false,
          message: 'Payment canceled.',
        );
      }
      return StripePaymentResult(
        success: false,
        message: e.error.localizedMessage ?? e.error.message,
      );
    } catch (e, st) {
      debugPrint('StripePaymentService: $e\n$st');
      return StripePaymentResult(success: false, message: e.toString());
    }
  }

  Future<String?> _fetchClientSecret({
    required int amountMinorUnits,
    required String currencyCode,
  }) async {
    final uri = Uri.parse(AppConfig.stripePaymentIntentUrl.trim());
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'amount': amountMinorUnits,
        'currency': currencyCode.toLowerCase(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final map = jsonDecode(response.body);
    if (map is! Map<String, dynamic>) {
      return null;
    }
    final secret = map['clientSecret'] ?? map['client_secret'];
    if (secret is String) {
      return secret;
    }
    return null;
  }

  Future<StripePaymentResult> _simulate(
    BuildContext context,
    double totalMyr,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Simulate payment'),
          content: Text(
            'No STRIPE_PAYMENT_INTENT_URL is configured. '
            'This dialog simulates charging RM${totalMyr.toStringAsFixed(2)} '
            'with Stripe test mode (e.g. card 4242 4242 4242 4242).\n\n'
            'Tap Complete to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Complete'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      return const StripePaymentResult(success: true);
    }
    return const StripePaymentResult(success: false, message: 'Canceled.');
  }

  int _myrToMinorUnits(double myr) {
    if (myr <= 0) {
      return 0;
    }
    return (myr * 100).round();
  }
}
