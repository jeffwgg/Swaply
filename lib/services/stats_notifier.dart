import 'package:flutter/material.dart';

class StatsNotifier {
  static final ValueNotifier<DateTime> refreshTrigger =
      ValueNotifier(DateTime.now());

  static void refresh() {
    refreshTrigger.value = DateTime.now();
  }
}