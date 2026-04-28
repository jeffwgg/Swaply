import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class TradeQrPayload {
  final int transactionId;
  final String role; // 'buyer' | 'seller'
  final String uid;

  const TradeQrPayload({
    required this.transactionId,
    required this.role,
    required this.uid,
  });

  static TradeQrPayload? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final tx = decoded['tx'];
      final role = decoded['role']?.toString();
      final uid = decoded['uid']?.toString();
      final txId = tx is num ? tx.toInt() : int.tryParse(tx?.toString() ?? '');
      if (txId == null) return null;
      if (role == null || (role != 'buyer' && role != 'seller')) return null;
      if (uid == null || uid.trim().isEmpty) return null;
      return TradeQrPayload(transactionId: txId, role: role, uid: uid);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {'tx': transactionId, 'role': role, 'uid': uid};
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    required this.title,
  });

  final String title;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;

  void _finish(String raw) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: MobileScanner(
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Camera is not available.\n\n'
                'If you are using an emulator/simulator, QR scanning may not work. '
                'Please test on a real device.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          );
        },
        onDetect: (capture) {
          final codes = capture.barcodes;
          if (codes.isEmpty) return;
          final raw = codes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;
          _finish(raw.trim());
        },
      ),
    );
  }
}

