import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StateStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
}

class PreferencesStore implements StateStore {
  static const key = 'anikku.library.v1';
  @override
  Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(key);
    return text == null ? null : jsonDecode(text) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, jsonEncode(value))) {
      throw StateError('Could not save your library.');
    }
  }
}

/// Atomic file persistence; tvOS deliberately uses its writable caches directory.
/// The OS may purge that directory. Export a backup for durable off-device storage.
class FileStateStore implements StateStore {
  FileStateStore({required this.directory});
  final Future<Directory> Function() directory;
  Future<File> _file() async {
    final folder = await directory();
    await folder.create(recursive: true);
    return File('${folder.path}/anikku-library-v1.json');
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }
}
