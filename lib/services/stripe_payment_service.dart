import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';

class StripePaymentResult {
  final bool success;
  final String? message;
  final String? paymentIntentId;

  const StripePaymentResult({
    required this.success,
    this.message,
    this.paymentIntentId,
  });
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
      final intentId = _paymentIntentIdFromClientSecret(clientSecret);

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Swaply',
          googlePay: PaymentSheetGooglePay(
            merchantCountryCode: 'MY',
            currencyCode: currencyCode.toUpperCase(),
            testEnv: true,
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return StripePaymentResult(success: true, paymentIntentId: intentId);
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

  /// Fetch the actual payment method used for a PaymentIntent.
  /// This relies on a server endpoint because Stripe secret key must stay server-side.
  Future<String?> fetchPaymentMethodType(String paymentIntentId) async {
    if (!AppConfig.hasStripePaymentIntentEndpoint) {
      return null;
    }
    final base = Uri.parse(AppConfig.stripePaymentIntentUrl.trim());
    final candidates = _derivePaymentMethodUris(base);

    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        for (final uri in candidates) {
          final response = await http.get(
            uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                'payment_intent_id': paymentIntentId,
              },
            ),
          );
          if (response.statusCode < 200 || response.statusCode >= 300) {
            continue;
          }
          final map = jsonDecode(response.body);
          if (map is! Map) continue;
          final val = map['paymentMethod'] ?? map['payment_method'];
          final method =
              val is String && val.trim().isNotEmpty ? val.trim() : null;
          if (method != null && method != 'unknown') return method;
        }
        // Redirect methods (GrabPay) can finalize charge slightly later.
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<Uri> _derivePaymentMethodUris(Uri createIntentUri) {
    // Common case: /create-payment-intent -> /payment-intent-method
    final path = createIntentUri.path;
    if (path.endsWith('/create-payment-intent')) {
      final a = createIntentUri.replace(
        path: path.replaceFirst(RegExp(r'/create-payment-intent$'), '/payment-intent-method'),
        query: '',
      );
      final b = createIntentUri.replace(
        path: '/payment-intent-method',
        query: '',
      );
      return [a, b];
    }
    // Fallback: append /payment-intent-method
    final newPath = path.endsWith('/')
        ? '${path}payment-intent-method'
        : '$path/payment-intent-method';
    final a = createIntentUri.replace(path: newPath, query: '');
    final b = createIntentUri.replace(path: '/payment-intent-method', query: '');
    return [a, b];
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

  String? _paymentIntentIdFromClientSecret(String clientSecret) {
    // Stripe client secret looks like: pi_XXX_secret_YYY
    final i = clientSecret.indexOf('_secret_');
    if (i <= 0) {
      return null;
    }
    return clientSecret.substring(0, i);
  }

  int _myrToMinorUnits(double myr) {
    if (myr <= 0) {
      return 0;
    }
    return (myr * 100).round();
  }
}
