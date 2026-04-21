import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ChatMediaCacheService {
  ChatMediaCacheService._();

  static final ChatMediaCacheService instance = ChatMediaCacheService._();

  Future<String?> cacheMediaFromUrl(String url, String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'chat_media_cache'));
      
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final localPath = p.join(cacheDir.path, fileName);
      final file = File(localPath);

      if (await file.exists()) {
        return localPath;
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return localPath;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<File?> getCachedMedia(String? cachedPath) async {
    if (cachedPath == null || cachedPath.isEmpty) {
      return null;
    }

    final file = File(cachedPath);
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<void> clearCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'chat_media_cache'));
      
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
