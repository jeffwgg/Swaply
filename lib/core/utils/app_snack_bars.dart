import 'package:flutter/material.dart';

/// Centralised, reusable snack bar helpers.
///
/// Usage:
///   AppSnackBars.success(context, 'Done!');
///   AppSnackBars.favourite(context, added: true);
///   AppSnackBars.error(context, 'Something went wrong');
abstract final class AppSnackBars {
  // ── Brand colours ────────────────────────────────────────────────────────
  static const _purple = Color(0xFF5A2CA0);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _amber = Color(0xFFF59E0B);

  // ── Core builder ─────────────────────────────────────────────────────────
  static void _show(
    BuildContext context, {
    required Widget content,
    required Color backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: duration,
      ),
    );
  }

  static Widget _row(IconData icon, String message, Color iconColor) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Favourite ─────────────────────────────────────────────────────────────
  /// Show a "Added to favourites" or "Removed from favourites" snack bar.
  static void favourite(BuildContext context, {bool added = true}) {
    _show(
      context,
      content: _row(
        added ? Icons.favorite : Icons.favorite_border,
        added ? 'Added to favourites!' : 'Removed from favourites',
        Colors.white,
      ),
      backgroundColor: added ? _green : _purple,
    );
  }

  // ── Generic success ───────────────────────────────────────────────────────
  static void success(BuildContext context, String message) {
    _show(
      context,
      content: _row(Icons.check_circle_outline_rounded, message, Colors.white),
      backgroundColor: _green,
    );
  }

  // ── Generic error ─────────────────────────────────────────────────────────
  static void error(BuildContext context, String message) {
    _show(
      context,
      content: _row(Icons.error_outline_rounded, message, Colors.white),
      backgroundColor: _red,
      duration: const Duration(seconds: 3),
    );
  }

  // ── Info / neutral ────────────────────────────────────────────────────────
  static void info(BuildContext context, String message) {
    _show(
      context,
      content: _row(Icons.info_outline_rounded, message, Colors.white),
      backgroundColor: _purple,
    );
  }

  // ── Warning ───────────────────────────────────────────────────────────────
  static void warning(BuildContext context, String message) {
    _show(
      context,
      content: _row(Icons.warning_amber_rounded, message, Colors.white),
      backgroundColor: _amber,
    );
  }
}
