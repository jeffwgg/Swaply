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
      version: 2,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createSchema(db);
        if (oldVersion < 2) {
          await db.execute('''
            ALTER TABLE transactions_cache ADD COLUMN item_status TEXT
          ''').catchError((_) {});
          await db.execute('''
            ALTER TABLE transactions_cache ADD COLUMN traded_item_status TEXT
          ''').catchError((_) {});
        }
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
      CREATE TABLE IF NOT EXISTS transactions_cache (
        transaction_id INTEGER PRIMARY KEY,
        buyer_id TEXT NOT NULL,
        seller_id TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        traded_item_id INTEGER,
        transaction_type TEXT,
        transaction_status TEXT,
        item_price REAL,
        shipping_fee REAL,
        total_amount REAL,
        fulfillment_method TEXT,
        address TEXT,
        created_at TEXT,

        -- denormalized snapshots for offline UI
        seller_username TEXT,
        item_name TEXT,
        item_image_url TEXT,
        item_category TEXT,
        item_status TEXT,
        traded_item_name TEXT,
        traded_item_image_url TEXT,
        traded_item_category TEXT,
        traded_item_status TEXT,

        is_synced INTEGER NOT NULL DEFAULT 1,
        failed INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        sync_error TEXT,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Forward-compatible columns for older DB installs.
    await db.execute('''
      ALTER TABLE transactions_cache ADD COLUMN item_status TEXT
    ''').catchError((_) {});
    await db.execute('''
      ALTER TABLE transactions_cache ADD COLUMN traded_item_status TEXT
    ''').catchError((_) {});

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_profile_items_cache_user_tab_updated
      ON profile_items_cache(user_id, tab_key, updated_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_cache_user_created
      ON transactions_cache(buyer_id, seller_id, created_at)
    ''');
  }
}
