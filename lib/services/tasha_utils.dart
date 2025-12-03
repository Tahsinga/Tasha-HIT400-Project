import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/vector_db.dart';

class TashaUtils {
  static Future<String?> getOpenAiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('OPENAI_API_KEY');
      if (key != null && key.trim().isNotEmpty) return key.trim();
    } catch (_) {}
    // dart-define fallback
    const envKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
    if (envKey.isNotEmpty) return envKey;
    return null;
  }

  static Future<String?> loadTxtFallbackForBook(String bookFileName) async {
    try {
      final base = _stripPdfExt(bookFileName);
      // 1) Prefer user TXT in Documents/TxtBooks
      final dir = await getApplicationDocumentsDirectory();
      final txtDir = Directory('${dir.path}/TxtBooks');
      try {
        final userFile = File('${txtDir.path}/$base.txt');
        if (await userFile.exists()) {
          return await userFile.readAsString();
        }
        // tolerant search inside TxtBooks
        if (await txtDir.exists()) {
          final candidates = txtDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.txt'))
              .toList();
          final normTarget = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          File? best;
          for (var c in candidates) {
            final name = c.path.split(Platform.pathSeparator).last;
            final cname = name.replaceAll('.txt', '').toLowerCase();
            final norm = cname.replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (norm == normTarget) {
              best = c;
              break;
            }
          }
          if (best == null) {
            for (var c in candidates) {
              final name = c.path.split(Platform.pathSeparator).last;
              final cname = name.replaceAll('.txt', '').toLowerCase();
              if (cname.contains(base.toLowerCase()) || base.toLowerCase().contains(cname)) {
                best = c;
                break;
              }
            }
          }
          if (best != null) {
            try {
              final raw = await best.readAsString();
              if (raw.trim().isNotEmpty) return raw;
            } catch (_) {}
          }
        }
      } catch (_) {}
      // 2) If no TxtBooks match, try Documents/table_of_contents
      try {
        final tocDir = Directory('${dir.path}/table_of_contents');
        final tocFile = File('${tocDir.path}/$base.txt');
        if (await tocFile.exists()) {
          final raw = await tocFile.readAsString();
          if (raw.trim().isNotEmpty) return raw;
        }
      } catch (_) {}
      // 3) Bundled asset exact match under assets/txt_books
      try {
        final assetPath = 'assets/txt_books/$base.txt';
        final raw = await rootBundle.loadString(assetPath);
        if (raw.trim().isNotEmpty) return raw;
      } catch (_) {}
      // 4) As a last resort, search bundled assets for a tolerant match (manifest scan)
      try {
        final manifestContent = await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifest = jsonDecode(manifestContent);
        final assetEntries = manifest.keys.where((k) => (k.startsWith('assets/txt_books/') || k.startsWith('assets/table_of_contents/')) && k.toLowerCase().endsWith('.txt'));
        final normTarget = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        String? found;
        for (var assetPath in assetEntries) {
          final fileName = assetPath.split('/').last;
          final nameNoExt = fileName.replaceAll('.txt', '').toLowerCase();
          final norm = nameNoExt.replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (norm == normTarget || nameNoExt.contains(base.toLowerCase()) || base.toLowerCase().contains(nameNoExt)) {
            found = assetPath;
            break;
          }
        }
        if (found != null) {
          final raw = await rootBundle.loadString(found);
          if (raw.trim().isNotEmpty) return raw;
        }
      } catch (_) {}
    } catch (_) {}
    return null;
  }

  static String _stripPdfExt(String fileName) {
    var b = fileName.toString();
    b = p.basename(b);
    final dot = b.lastIndexOf('.');
    if (dot > 0) b = b.substring(0, dot);
    return b;
  }
}
