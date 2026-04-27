import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSearchHistoryRepository {
  LocalSearchHistoryRepository();

  static const int _maxEntries = 5;
  static const String _storageKey = 'discover_recent_searches';

  Future<void> saveQuery(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final current = await listRecent();
    final deduplicated = <String>[
      normalized,
      ...current.where((entry) => entry.toLowerCase() != normalized.toLowerCase()),
    ];
    final limited = deduplicated.take(_maxEntries).toList(growable: false);
    await prefs.setString(_storageKey, jsonEncode(limited));
  }

  Future<List<String>> listRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .map((row) => row.toString().trim())
        .where((query) => query.isNotEmpty)
        .take(_maxEntries)
        .toList(growable: false);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
