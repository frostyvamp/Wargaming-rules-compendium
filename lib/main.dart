import 'dart:io'; // Gives us Platform checks (isWindows, isAndroid, etc.)
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/home_screen.dart';

void main() {
  // sqflite's native bridge only exists on Android/iOS/macOS.
  // On Windows/Linux desktop, we swap in the FFI factory,
  // which talks to SQLite's C library directly.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const RulesRepositoryApp());
}

/// RulesRepositoryApp is the root widget of our application.
class RulesRepositoryApp extends StatelessWidget {
  const RulesRepositoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rules Repository',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}