/// Represents a tabletop game (e.g., BattleTech, Trench Crusade).
class Game {
  final int? id; // Null when creating a new game, assigned by DB upon insertion
  final String name;

  Game({this.id, required this.name});

  // Converts a Game object into a Map that SQLite can understand
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  // Converts a SQLite row (Map) back into a Game object
  factory Game.fromMap(Map<String, dynamic> map) {
    return Game(
      id: map['id'],
      name: map['name'],
    );
  }
}

/// Represents a specific rulebook within a Game (e.g., Total Warfare).
/// Represents one rules source within a Game (e.g., Total Warfare).
/// sourceType future-proofs us: 'pdf' today, 'text' or 'html' later
/// for things like Kings of War errata pasted from their compendium.
/// A (possibly nested) folder within a Game for organizing books,
/// e.g. "Core Rulebooks" or "Technical Readouts".
class Folder {
  final int? id;
  final int gameId;
  final int? parentFolderId; // null = top-level folder within the game
  final String name;

  Folder({
    this.id,
    required this.gameId,
    this.parentFolderId,
    required this.name,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'game_id': gameId,
      'parent_folder_id': parentFolderId,
      'name': name,
    };
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'],
      gameId: map['game_id'],
      parentFolderId: map['parent_folder_id'],
      name: map['name'],
    );
  }
}

/// Represents one rules source within a Game. folderId null means the
/// book sits at the game root; folders remain entirely optional.
class Book {
  final int? id;
  final int gameId;
  final String title;
  final String filePath;
  final String sourceType;
  final int lastPage;
  final int? folderId;

  Book({
    this.id,
    required this.gameId,
    required this.title,
    required this.filePath,
    this.sourceType = 'pdf',
    this.lastPage = 1,
    this.folderId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'game_id': gameId,
      'title': title,
      'file_path': filePath,
      'source_type': sourceType,
      'last_page': lastPage,
      'folder_id': folderId,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'],
      gameId: map['game_id'],
      title: map['title'],
      filePath: map['file_path'],
      sourceType: map['source_type'] ?? 'pdf',
      lastPage: map['last_page'] ?? 1,
      folderId: map['folder_id'],
    );
  }
}