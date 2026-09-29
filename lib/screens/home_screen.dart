import 'package:flutter/material.dart';
import '../models/game_model.dart';
import '../services/database_service.dart';
import 'game_detail_screen.dart';
import '../services/file_service.dart';

/// HomeScreen is the main landing page of the app.
/// It is a StatefulWidget because the list of games changes over time,
/// and the UI must rebuild itself to reflect those changes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Our single, shared connection to the SQLite database
  final DatabaseService _db = DatabaseService.instance;
  final FileService _files = FileService.instance;
  // Controls the TextField so we can read and clear the typed text
  final TextEditingController _nameController = TextEditingController();

  // Local state: the list of games loaded from the database
  List<Game> _games = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // initState cannot be async, so we fire the load and let
    // setState rebuild the screen when the data arrives.
    _loadGames();
  }

  @override
  void dispose() {
    // Always dispose controllers to free memory when the screen dies
    _nameController.dispose();
    super.dispose();
  }

  /// Reads all games from SQLite and refreshes the UI
  Future<void> _loadGames() async {
    final games = await _db.getAllGames();
    setState(() {
      _games = games;
      _isLoading = false;
    });
  }

  /// Inserts a new game, then refreshes the list
  Future<void> _addGame() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    try {
      await _db.insertGame(Game(name: name));
      _nameController.clear();
      await _loadGames();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" added to your library')),
        );
      }
    } catch (e) {
      // The games table has a UNIQUE constraint on name,
      // so adding a duplicate throws an error we catch here.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That game already exists in your library')),
        );
      }
    }
  }

  /// Deletes a game by ID, then refreshes the list
  Future<void> _deleteGame(Game game) async {
    // Remove the game's copied PDF files from storage first,
    // then delete the game row; CASCADE removes the book rows.
    final books = await _db.getBooksForGame(game.id!);
    for (final book in books) {
      await _files.deleteFile(book.filePath);
    }
    await _db.deleteGame(game.id!);
    await _loadGames();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${game.name}" removed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rules Repository'),
      ),
      body: Column(
        children: [
          // The game list takes up all remaining vertical space
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _games.isEmpty
                    ? const Center(
                        child: Text('No games yet. Add your first below!'),
                      )
                    : ListView.builder(
                        itemCount: _games.length,
                        itemBuilder: (context, index) {
                          final game = _games[index];
                           return ListTile(
                            leading: const Icon(Icons.sports_esports),
                            title: Text(game.name),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GameDetailScreen(game: game),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteGame(game),
                            ),
                          );
                        },
                      ),
          ),
          // Input bar pinned to the bottom of the screen.
          // FIX (Fold5 gesture-nav overlap): SafeArea keeps it clear of the
          // Android navigation bar in edge-to-edge mode.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'Game name (e.g., BattleTech)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addGame,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}