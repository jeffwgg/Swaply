import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swaply/models/item_draft.dart';

class LocalDraftRepository {
  LocalDraftRepository();
  static const String _storageKey = 'create_item_draft';

  Future<void> upsertDraft(ItemDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final map = draft.toMap();
    map['image_urls'] = await _sanitizeImageUrls(draft.imageUrls ?? <String>[]);
    map['updated_at'] = DateTime.now().toIso8601String();
    await prefs.setString(_storageKey, jsonEncode(map));
  }

  Future<ItemDraft?> getDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final data = Map<String, dynamic>.from(decoded);
    final rawImages = data['image_urls'];
    if (rawImages is List) {
      data['image_urls'] = rawImages.map((item) => item.toString()).toList();
    } else if (rawImages is String && rawImages.isNotEmpty) {
      data['image_urls'] = List<String>.from(jsonDecode(rawImages) as List);
    } else {
      data['image_urls'] = <String>[];
    }

    return ItemDraft.fromMap(data);
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<List<String>> _sanitizeImageUrls(List<String> imageUrls) async {
    final tempDir = await getTemporaryDirectory();
    final appDir = await getApplicationDocumentsDirectory();
    return imageUrls.where((imagePath) {
      if (imagePath.startsWith('http') || imagePath.startsWith('assets/')) {
        return true;
      }
      final file = File(imagePath);
      if (!file.existsSync()) {
        return false;
      }
      final normalized = path.normalize(file.path);
      final tempRoot = path.normalize(tempDir.path);
      final appRoot = path.normalize(appDir.path);
      return path.isWithin(tempRoot, normalized) || path.isWithin(appRoot, normalized);
    }).toList(growable: false);
  }
}
