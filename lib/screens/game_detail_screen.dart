import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/game_model.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import 'reader_screen.dart';

/// Browses one level of a game's library tree: the folders and books
/// inside the current folder (the game root when folderId is null).
/// Tapping a folder pushes another copy of this screen, which gives
/// unlimited nesting depth with the back arrow climbing one level.
class GameDetailScreen extends StatefulWidget {
  final Game game;
  final int? folderId;
  final String? folderName;

  const GameDetailScreen({
    super.key,
    required this.game,
    this.folderId,
    this.folderName,
  });

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  final DatabaseService _db = DatabaseService.instance;
  final FileService _files = FileService.instance;

  List<Folder> _folders = [];
  List<Book> _books = [];
  bool _isLoading = true;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await _db.getFoldersIn(widget.game.id!, widget.folderId);
    final books = await _db.getBooksIn(widget.game.id!, widget.folderId);
    setState(() {
      _folders = folders;
      _books = books;
      _isLoading = false;
    });
  }

  /// Picker-first import: choose the file, then confirm or edit the
  /// name that defaults to the file's own name.
  Future<void> _importPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.first.path == null) return;

    final picked = result.files.first;
    final dot = picked.name.lastIndexOf('.');
    final defaultName = dot > 0 ? picked.name.substring(0, dot) : picked.name;

    final title = await _promptForName(defaultName, 'Name this book');
    if (title == null) return; // Cancelled: nothing is copied or saved.

    setState(() => _isImporting = true);
    try {
      final internalPath = await _files.importPdf(picked.path!, title);
      await _db.insertBook(Book(
        gameId: widget.game.id!,
        title: title,
        filePath: internalPath,
        folderId: widget.folderId,
      ));
      await _load();
      _snack('"$title" imported');
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// Shared naming dialog. Returns the trimmed name, or null on cancel.
  Future<String?> _promptForName(String initial, String heading) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(heading),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final trimmed = result?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _renameBook(Book book) async {
    final name = await _promptForName(book.title, 'Rename book');
    if (name == null) return;
    await _db.updateBookTitle(book.id!, name);
    await _load();
    _snack('Renamed to "$name"');
  }

  Future<void> _deleteBook(Book book) async {
    await _files.deleteFile(book.filePath);
    await _db.deleteBook(book.id!);
    await _load();
    _snack('"${book.title}" removed');
  }

  Future<void> _createFolder() async {
    final name = await _promptForName('', 'New folder');
    if (name == null) return;
    await _db.insertFolder(Folder(
      gameId: widget.game.id!,
      parentFolderId: widget.folderId,
      name: name,
    ));
    await _load();
    _snack('Folder "$name" created');
  }

  Future<void> _deleteFolder(Folder folder) async {
    final ids = await _db.folderTreeIds(folder.id!);
    int bookCount = 0;
    for (final id in ids) {
      bookCount += (await _db.getBooksByFolder(id)).length;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: Text(bookCount == 0
            ? 'This folder and any subfolders inside it will be removed.'
            : 'This folder, its subfolders, and $bookCount imported '
                'book(s) inside them will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in ids) {
      for (final book in await _db.getBooksByFolder(id)) {
        await _files.deleteFile(book.filePath);
      }
    }
    await _db.deleteFolders(ids);
    await _load();
    _snack('Folder "${folder.name}" deleted');
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folderName ?? widget.game.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: _createFolder,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _folders.isEmpty && _books.isEmpty
                    ? const Center(
                        child: Text(
                          'Nothing here yet.\nImport a PDF below, or create '
                          'a folder to organize future imports.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        children: [
                          for (final folder in _folders)
                            ListTile(
                              leading: const Icon(Icons.folder),
                              title: Text(folder.name),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GameDetailScreen(
                                      game: widget.game,
                                      folderId: folder.id,
                                      folderName: folder.name,
                                    ),
                                  ),
                                );
                                await _load();
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteFolder(folder),
                              ),
                            ),
                          for (final book in _books)
                            ListTile(
                              leading: const Icon(Icons.picture_as_pdf),
                              title: Text(book.title),
                              subtitle: Text(book.sourceType.toUpperCase()),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReaderScreen(book: book),
                                  ),
                                );
                                await _load();
                              },
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (action) {
                                  if (action == 'rename') {
                                    _renameBook(book);
                                  } else if (action == 'delete') {
                                    _deleteBook(book);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 'rename', child: Text('Rename')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ),
                        ],
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton.icon(
              onPressed: _isImporting ? null : _importPdf,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: const Text('Import PDF'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}