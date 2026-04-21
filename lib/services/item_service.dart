import '../models/item_draft.dart';
import '../models/item_listing.dart';
import '../repositories/favourite_repository.dart';
import '../repositories/items_repository.dart';
import '../repositories/local/local_draft_repository.dart';
import '../repositories/local/local_favourites_repository.dart';
import '../repositories/local/local_items_repository.dart';

class ItemService {
  final ItemsRepository _remote;
  final FavouriteRepository _remoteFav;
  final LocalItemsRepository _localItems;
  final LocalFavouritesRepository _localFav;
  final LocalDraftRepository _localDraft;

  ItemService({
    ItemsRepository? remote,
    FavouriteRepository? remoteFav,
    LocalItemsRepository? localItems,
    LocalFavouritesRepository? localFav,
    LocalDraftRepository? localDraft,
  }) : _remote = remote ?? ItemsRepository(),
        _remoteFav = remoteFav ?? FavouriteRepository(),
        _localItems = localItems ?? LocalItemsRepository(),
        _localFav = localFav ?? LocalFavouritesRepository(),
        _localDraft = localDraft ?? LocalDraftRepository();

  Future<ItemDraft?> getDraft() async {
    return await _localDraft.getDraft();
  }

  Future<void> clearDraft() async {
    return await _localDraft.clearDraft();
  }

  Future<void> saveDraft(ItemDraft draft) async {
    await _localDraft.upsertDraft(draft);
  }

  Future<void> submitDraft() async {
    final draft = await _localDraft.getDraft();
    if (draft == null) return;

    try {
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
        imageUrls: draft.imageUrls ?? <String>[],
        preference: draft.preference,
        repliedTo: draft.repliedTo,
        createdAt: draft.createdAt,
        address: draft.address,
        latitude: draft.latitude,
        longitude: draft.longitude,
      );

      await _remote.create(item);

      await _localItems.insertUserItem(item);
      await _localDraft.clearDraft();
    } catch (_) {
      // store for retry
      await _localDraft.markAsPendingUpload();
    }
  }

  Future<List<ItemListing>> loadItems({
    String? userId,
    String? category,
    String? listingType,
    String? searchQuery,
  }) async {
    final local = await _localItems.getCachedItems();
    final remoteFuture = _remote.getDiscoverList(
      userId: userId,
      category: category,
      listingType: listingType,
      searchQuery: searchQuery,
    );
    final shouldCacheUnfiltered =
        (category == null || category == 'All') &&
        (listingType == null || listingType == 'both') &&
        (searchQuery == null || searchQuery.trim().isEmpty);

    if (local.isNotEmpty) {
      try {
        final remote = await remoteFuture.timeout(
          const Duration(milliseconds: 400),
        );

        if (shouldCacheUnfiltered) {
          await _localItems.replaceCache(remote);
        } else {
          await _localItems.mergeCache(remote);
        }
        return remote;
      } catch (_) {
        _refreshCache(remoteFuture, shouldCacheUnfiltered: shouldCacheUnfiltered);
        return _filterCachedItems(
          local,
          userId: userId,
          category: category,
          listingType: listingType,
          searchQuery: searchQuery,
        );
      }
    }

    try {
      final remote = await remoteFuture;
      if (shouldCacheUnfiltered) {
        await _localItems.replaceCache(remote);
      } else {
        await _localItems.mergeCache(remote);
      }
      return remote;
    } catch (_) {
      return _filterCachedItems(
        local,
        userId: userId,
        category: category,
        listingType: listingType,
        searchQuery: searchQuery,
      );
    }
  }

  Future<bool> toggleFavourite(int itemId, String userId) async {
    final isFav = await _localFav.isFavourite(userId, itemId);
    final newState = !isFav;

    if (isFav) {
      await _localFav.markDeleted(userId, itemId);
    } else {
      await _localFav.insert(userId, itemId);
    }

    try {
      await _remoteFav.toggleFavourite(userId, itemId);

      await _localFav.markSynced(userId, itemId);
    } catch (_) {
      // leave unsynced → retry later
    }

    return newState;
  }

  Future<void> flushFavourites() async {
    final pending = await _localFav.getUnsynced();

    for (final fav in pending) {
      try {
        final userId = (fav['user_id'] ?? '').toString();
        final itemId = fav['item_id'] as int?;
        if (userId.isEmpty || itemId == null) {
          continue;
        }

        await _remoteFav.toggleFavourite(userId, itemId);

        await _localFav.markSynced(userId, itemId);
      } catch (_) {
        break;
      }
    }
  }

  Future<List<ItemListing>> loadUserItems(String userId) async {
    final local = await _localItems.getUserItems(userId);

    try {
      final remote = await _remote.getUserItems(userId);
      await _localItems.replaceUserItems(remote);
      return remote;
    } catch (_) {
      return local;
    }
  }

  Future<void> retryPending() async {
    await flushFavourites();
    await _retryPendingDraft();
    await _retryUnsyncedItems();
  }

  void _refreshCache(
    Future<List<ItemListing>> remoteFuture, {
    required bool shouldCacheUnfiltered,
  }) {
    remoteFuture.then((remote) async {
      if (shouldCacheUnfiltered) {
        await _localItems.replaceCache(remote);
      } else {
        await _localItems.mergeCache(remote);
      }
    }).catchError((_) {});
  }

  List<ItemListing> _filterCachedItems(
    List<ItemListing> items, {
    String? userId,
    String? category,
    String? listingType,
    String? searchQuery,
  }) {
    final normalizedQuery = (searchQuery ?? '').trim().toLowerCase();
    return items.where((item) {
      if (item.status != 'available' || item.repliedTo != null) {
        return false;
      }
      if (userId != null && item.ownerId == userId && normalizedQuery.isEmpty) {
        return false;
      }
      if (category != null && category != 'All' && item.category != category) {
        return false;
      }
      if (listingType == 'sell' &&
          item.listingType != 'sell' &&
          item.listingType != 'both') {
        return false;
      }
      if (listingType == 'trade' &&
          item.listingType != 'trade' &&
          item.listingType != 'both') {
        return false;
      }
      if (normalizedQuery.isNotEmpty &&
          !item.name.toLowerCase().contains(normalizedQuery)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _retryPendingDraft() async {
    final draft = await _localDraft.getDraft();
    if (draft == null || !draft.isPendingSubmit) {
      return;
    }
    await submitDraft();
  }

  Future<void> _retryUnsyncedItems() async {
    // Placeholder for unsynced item update/delete queue.
    // Current offline sync scope covers draft submit + favourites.
  }
}