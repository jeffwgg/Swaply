import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/item_draft.dart';
import '../models/item_listing.dart';
import '../repositories/favourite_repository.dart';
import '../repositories/items_repository.dart';
import '../repositories/local/local_draft_repository.dart';
import '../repositories/local/local_search_history_repository.dart';

class ItemService {
  final ItemsRepository _remote;
  final FavouriteRepository _remoteFav;
  final LocalDraftRepository _localDraft;
  final LocalSearchHistoryRepository _localSearchHistory;

  ItemService({
    ItemsRepository? remote,
    FavouriteRepository? remoteFav,
    LocalDraftRepository? localDraft,
    LocalSearchHistoryRepository? localSearchHistory,
  })
      : _remote = remote ?? ItemsRepository(),
        _remoteFav = remoteFav ?? FavouriteRepository(),
        _localDraft = localDraft ?? LocalDraftRepository(),
        _localSearchHistory =
            localSearchHistory ?? LocalSearchHistoryRepository();

  Future<ItemDraft?> getDraft() async {
    return await _localDraft.getDraft();
  }

  Future<void> saveDraft(ItemDraft draft) async {
    await _localDraft.upsertDraft(draft);
  }

  Future<void> clearDraft() async {
    await _localDraft.clearDraft();
  }

  Future<void> saveSearchQuery(String query) async {
    await _localSearchHistory.saveQuery(query);
  }

  Future<List<String>> loadRecentSearchQueries() async {
    return await _localSearchHistory.listRecent();
  }

  Future<void> clearSearchHistory() async {
    await _localSearchHistory.clear();
  }

  Future<void> submitDraft() async {
    final draft = await _localDraft.getDraft();
    if (draft == null) return;

    final lastId = await _remote.getLastId();
    final nextIdNum = (lastId ?? 0) + 1;

    final item = ItemListing(
      id: nextIdNum,
      name: draft.name ?? '',
      description: draft.description ?? '',
      price: draft.price,
      listingType: draft.listingType ?? 'both',
      ownerId: draft.ownerId,
      status: draft.repliedTo == null ? 'available' : 'pending',
      category: draft.category ?? 'Others',
      imageUrls: draft.imageUrls ?? [],
      preference: draft.preference,
      repliedTo: draft.repliedTo,
      createdAt: draft.createdAt,
      address: draft.address,
      latitude: draft.latitude,
      longitude: draft.longitude,
    );

    await _remote.create(item);
  }

  Future<List<ItemListing>> loadItems({
    String? userId,
    String? category,
    String? listingType,
    String? searchQuery,
  }) async {
    return await _remote.getDiscoverList(
      userId: userId,
      category: category,
      listingType: listingType,
      searchQuery: searchQuery,
    );
  }

  Future<bool> toggleFavourite(int itemId, String userId) async {
    return await _remoteFav.toggleFavourite(userId, itemId);
  }

  static Future<String> cacheImage(String url) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = '${url.hashCode}.jpg';
      final filePath = '${dir.path}/cached_images/$fileName';

      final file = File(filePath);

      // ✅ If already cached → reuse
      if (await file.exists()) {
        return filePath;
      }

      // Ensure directory exists
      await Directory('${dir.path}/cached_images')
          .create(recursive: true);

      // Download
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        throw Exception('Failed to download image');
      }
    } catch (e) {
      return url; // fallback to original URL if anything fails
    }
  }
}