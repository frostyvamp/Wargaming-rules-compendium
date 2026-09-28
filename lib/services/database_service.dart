import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/game_model.dart';

class DatabaseService {
  // Singleton: one shared connection for the whole app
  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rules_repository.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final appDir = await getApplicationSupportDirectory();
    final path = join(appDir.path, filePath);

    return await openDatabase(
      path,
      // Bumped from 1 to 2. Existing installs run onUpgrade;
      // brand new installs run onCreate with the v2 schema.
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: (db) async {
        // SQLite turns foreign key enforcement OFF by default.
        // This pragma is what makes ON DELETE CASCADE actually work.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // Runs only when the database file is created for the first time
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        parent_folder_id INTEGER,
        name TEXT NOT NULL,
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'pdf',
        last_page INTEGER NOT NULL DEFAULT 1,
        folder_id INTEGER,
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE books ADD COLUMN source_type TEXT NOT NULL DEFAULT 'pdf'",
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE books ADD COLUMN last_page INTEGER NOT NULL DEFAULT 1",
      );
    }
        if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE folders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          game_id INTEGER NOT NULL,
          parent_folder_id INTEGER,
          name TEXT NOT NULL,
          FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        ALTER TABLE books ADD COLUMN folder_id INTEGER
      ''');
    }
  }

  // --- Games ---
  Future<int> insertGame(Game game) async {
    final db = await database;
    return await db.insert('games', game.toMap());
  }

  Future<List<Game>> getAllGames() async {
    final db = await database;
    final maps = await db.query('games');
    return maps.map((map) => Game.fromMap(map)).toList();
  }

  Future<int> deleteGame(int id) async {
    final db = await database;
    return await db.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  // --- Books ---
  Future<int> insertBook(Book book) async {
    final db = await database;
    return await db.insert('books', book.toMap());
  }

  Future<List<Book>> getBooksForGame(int gameId) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'game_id = ?',
      whereArgs: [gameId],
    );
    return maps.map((map) => Book.fromMap(map)).toList();
  }
    Future<Book?> getBook(int id) async {
    final db = await database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }
    Future<int> updateBookLastPage(int id, int page) async {
    final db = await database;
    return await db.update(
      'books',
      {'last_page': page},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
    Future<int> updateBookTitle(int id, String title) async {
    final db = await database;
    return await db.update(
      'books',
      {'title': title},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
    // --- Folders ---
  Future<int> insertFolder(Folder folder) async {
    final db = await database;
    return await db.insert('folders', folder.toMap());
  }

  Future<List<Folder>> getFoldersIn(int gameId, int? parentFolderId) async {
    final db = await database;
    final maps = await db.query(
      'folders',
      where: parentFolderId == null
          ? 'game_id = ? AND parent_folder_id IS NULL'
          : 'game_id = ? AND parent_folder_id = ?',
      whereArgs:
          parentFolderId == null ? [gameId] : [gameId, parentFolderId],
    );
    return maps.map((map) => Folder.fromMap(map)).toList();
  }

  Future<List<Folder>> getSubfolders(int parentFolderId) async {
    final db = await database;
    final maps = await db.query(
      'folders',
      where: 'parent_folder_id = ?',
      whereArgs: [parentFolderId],
    );
    return maps.map((map) => Folder.fromMap(map)).toList();
  }

  Future<List<Book>> getBooksIn(int gameId, int? folderId) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: folderId == null
          ? 'game_id = ? AND folder_id IS NULL'
          : 'game_id = ? AND folder_id = ?',
      whereArgs: folderId == null ? [gameId] : [gameId, folderId],
    );
    return maps.map((map) => Book.fromMap(map)).toList();
  }

  Future<List<Book>> getBooksByFolder(int folderId) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
    return maps.map((map) => Book.fromMap(map)).toList();
  }

  /// Recursively collects every folder id at or below [folderId].
  Future<List<int>> folderTreeIds(int folderId) async {
    final ids = <int>[folderId];
    for (final child in await getSubfolders(folderId)) {
      ids.addAll(await folderTreeIds(child.id!));
    }
    return ids;
  }

  /// Deletes folder rows and their book rows explicitly, so deletion
  /// semantics never depend on foreign-key subtleties.
  Future<void> deleteFolders(List<int> ids) async {
    final db = await database;
    for (final id in ids) {
      await db.delete('books', where: 'folder_id = ?', whereArgs: [id]);
      await db.delete('folders', where: 'id = ?', whereArgs: [id]);
    }
  }
}