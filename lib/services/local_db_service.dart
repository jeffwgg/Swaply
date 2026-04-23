import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  LocalDbService._();

  static final LocalDbService instance = LocalDbService._();

  static const _dbName = 'swaply_local.db';

  Database? _db;

  Future<void> initialize() async {
    await database;
  }

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) {
      return existing;
    }

    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    final db = await openDatabase(
      fullPath,
      version: 1,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onOpen: (db) async {
        await _createSchema(db);
      },
    );
    _db = db;

    return _db!;
  }

  Future<void> close() async {
    final existing = _db;
    if (existing == null) {
      return;
    }
    await existing.close();
    _db = null;
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_threads_cache (
        id INTEGER PRIMARY KEY,
        user1_id TEXT NOT NULL,
        user2_id TEXT NOT NULL,
        user1_name TEXT,
        user2_name TEXT,
        user1_profile_image TEXT,
        user2_profile_image TEXT,
        item_id INTEGER,
        item_title TEXT,
        item_owner_id TEXT,
        item_image_urls TEXT,
        last_message TEXT,
        pinned_message_id INTEGER,
        pinned_at TEXT,
        updated_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 1,
        failed INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages_cache (
        id INTEGER PRIMARY KEY,
        client_generated_id TEXT UNIQUE,
        chat_id INTEGER NOT NULL,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        cached_media_path TEXT,
        read_at TEXT,
        edited_at TEXT,
        deleted_at TEXT,
        deleted_by TEXT,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 1,
        failed INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        sync_error TEXT
      )
    ''');

    await db.execute('''
      ALTER TABLE chat_messages_cache ADD COLUMN cached_media_path TEXT
    ''').catchError((_) {});

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_messages_cache_chat_created
      ON chat_messages_cache(chat_id, created_at)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_outgoing_messages (
        client_generated_id TEXT PRIMARY KEY,
        temp_message_id INTEGER NOT NULL,
        chat_id INTEGER NOT NULL,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        failed INTEGER NOT NULL DEFAULT 0,
        last_attempt_at TEXT,
        last_error TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_outgoing_messages_chat
      ON pending_outgoing_messages(chat_id, created_at)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_draft (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT,
        description TEXT,
        price REAL,
        listing_type TEXT,
        owner_id TEXT,
        category TEXT,
        image_urls TEXT,
        preference TEXT,
        replied_to INTEGER,
        address TEXT,
        latitude REAL,
        longitude REAL,
  
        is_pending_upload INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0,
        sync_error TEXT,
      
        updated_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
  ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_draft_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        draft_id INTEGER NOT NULL,
        image_bytes BLOB NOT NULL,
        image_ext TEXT,
        sort_order INTEGER NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_item_draft_images_draft_sort
      ON item_draft_images(draft_id, sort_order)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL UNIQUE,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_search_history_updated_at
      ON search_history(updated_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS profile_items_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        tab_key TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(user_id, tab_key, item_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_profile_items_cache_user_tab_updated
      ON profile_items_cache(user_id, tab_key, updated_at DESC)
    ''');
  }
}
