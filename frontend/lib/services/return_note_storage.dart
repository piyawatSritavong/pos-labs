import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class ReturnNoteStorage {
  static const String _storageKey = 'pos_return_notes';

  static List<Map<String, dynamic>> loadNotes() {
    if (!kIsWeb) return [];
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      // ignore parse error
    }
    return [];
  }

  static Future<void> appendNote(Map<String, dynamic> note) async {
    if (!kIsWeb) return;
    final notes = loadNotes();
    notes.insert(0, note);
    if (notes.length > 200) {
      notes.removeRange(200, notes.length);
    }
    html.window.localStorage[_storageKey] = jsonEncode(notes);
  }
}
