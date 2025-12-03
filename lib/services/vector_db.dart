// ignore_for_file: avoid_print

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class VectorDB {
  static Database? _db;

  static Future<Database> openDb() async {
    if (_db != null) return _db!;
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'rag_vectors.db');
    _db = await openDatabase(path, version: 3, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE chunks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book TEXT,
          start_page INTEGER,
          end_page INTEGER,
          text TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE embeddings (
          chunk_id INTEGER PRIMARY KEY,
          embedding BLOB
        );
      ''');
      await db.execute('''
        CREATE TABLE qa_pairs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book TEXT,
          question TEXT,
          answer TEXT,
          question_embedding BLOB,
          unsynced INTEGER DEFAULT 0
        );
      ''');
      await db.execute('''
        CREATE TABLE query_embeddings (
          query TEXT PRIMARY KEY,
          embedding BLOB
        );
      ''');
      await db.execute('''
        CREATE TABLE books (
          book TEXT PRIMARY KEY,
          toc TEXT,
          full_text TEXT,
          cover BLOB,
          cover_path TEXT
        );
      ''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      try {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE qa_pairs ADD COLUMN unsynced INTEGER DEFAULT 0');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS books (
              book TEXT PRIMARY KEY,
              toc TEXT,
              full_text TEXT,
              cover BLOB,
              cover_path TEXT
            );
          ''');
        }
      } catch (_) {}
    });
    return _db!;
  }

  // Upsert book metadata: toc text, full_text, and optional cover bytes/path
  static Future<void> upsertBook(String book, {String? toc, String? fullText, Uint8List? coverBytes, String? coverPath}) async {
    final db = await openDb();
    final existing = await db.query('books', where: 'book = ?', whereArgs: [book]);
    final values = <String, Object?>{};
    if (toc != null) values['toc'] = toc;
    if (fullText != null) values['full_text'] = fullText;
    if (coverBytes != null) values['cover'] = coverBytes;
    if (coverPath != null) values['cover_path'] = coverPath;
    if (existing.isEmpty) {
      values['book'] = book;
      await db.insert('books', values);
    } else {
      await db.update('books', values, where: 'book = ?', whereArgs: [book]);
    }
  }

  // Return full_text if present, otherwise toc, or null
  static Future<String?> getBookText(String book) async {
    final db = await openDb();
    final rows = await db.query('books', columns: ['full_text', 'toc'], where: 'book = ?', whereArgs: [book]);
      if (rows.isEmpty) return '';
    final r = rows.first;
    final full = r['full_text'] as String?;
    if (full != null && full.trim().isNotEmpty) return full;
    final toc = r['toc'] as String?;
    if (toc != null && toc.trim().isNotEmpty) return toc;
      return '';
  }

  // Get cover bytes (if stored)
  static Future<Uint8List?> getBookCover(String book) async {
    final db = await openDb();
    final rows = await db.query('books', columns: ['cover'], where: 'book = ?', whereArgs: [book]);
    if (rows.isEmpty) return null;
    final b = rows.first['cover'] as Uint8List?;
    return b;
  }

  static Future<int> insertChunk(String book, int startPage, int endPage, String text, List<double>? embedding) async {
    final db = await openDb();
    final bookId = normalizeBookId(book);
    final id = await db.insert('chunks', {'book': bookId, 'start_page': startPage, 'end_page': endPage, 'text': text});
    if (embedding != null) {
      final embBytes = _doubleListToByteData(embedding).buffer.asUint8List();
      await db.insert('embeddings', {'chunk_id': id, 'embedding': embBytes});
    }
    return id;
  }

  // Insert multiple chunks in a single transaction. Each item in 'items' should have: start_page, end_page, text, embedding (List<double> or null)
  static Future<void> insertChunkBatch(String book, List<Map<String, dynamic>> items) async {
    final db = await openDb();
    final bookId = normalizeBookId(book);
    await db.transaction((txn) async {
      for (var it in items) {
        final sp = it['start_page'] as int? ?? 0;
        final ep = it['end_page'] as int? ?? sp;
        final text = it['text']?.toString() ?? '';
        final embedding = it['embedding'] as List<double>?;
        final id = await txn.insert('chunks', {'book': bookId, 'start_page': sp, 'end_page': ep, 'text': text});
        if (embedding != null) {
          final embBytes = _doubleListToByteData(embedding).buffer.asUint8List();
          await txn.insert('embeddings', {'chunk_id': id, 'embedding': embBytes});
        }
      }
    });
  }

  static Future<int> chunksCountForBook(String book) async {
    final db = await openDb();
    final bookId = normalizeBookId(book);
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM chunks WHERE book = ?', [bookId]);
    if (res.isEmpty) return 0;
    return (res.first['c'] as int?) ?? 0;
  }

  static Future<List<Map<String, dynamic>>> chunksForBook(String book) async {
    final db = await openDb();
    final bookId = normalizeBookId(book);
    // Use LEFT JOIN so we get chunks even if embeddings don't exist (null embedding is ok for text-only search)
    final rows = await db.rawQuery('SELECT c.id, c.book, c.start_page, c.end_page, c.text, e.embedding FROM chunks c LEFT JOIN embeddings e ON c.id = e.chunk_id WHERE c.book = ?', [bookId]);
    return rows;
  }

  static Future<List<Map<String, dynamic>>> allChunks() async {
    final db = await openDb();
    // Use LEFT JOIN so we get all chunks even if embeddings don't exist
    final rows = await db.rawQuery('SELECT c.id, c.book, c.start_page, c.end_page, c.text, e.embedding FROM chunks c LEFT JOIN embeddings e ON c.id = e.chunk_id');
    return rows;
  }

  /// Index a long text for a book by splitting into sequential word-based chunks.
  /// This uses simple, fast word-based chunking (NOT overlapping) to avoid exponential duplication.
  /// If an `embedder` callback is provided, it will be used to compute embeddings for each chunk.
  /// Returns number of chunks inserted.
  static Future<int> indexTextForBook(String book, String text, {Future<List<double>> Function(String)? embedder, int chunkSize = 1000}) async {
    final db = await openDb();
    final bookId = normalizeBookId(book);
    if (text.trim().isEmpty) return 0;

    // Split into words using simple whitespace split
    final words = text.split(RegExp(r'\s+'));
    if (words.isEmpty) return 0;

    print('[VectorDB] indexTextForBook: book=$bookId, ${words.length} words, chunkSize=$chunkSize');

    // Create sequential chunks (NO overlapping to avoid explosion)
    final chunks = <String>[];
    for (var i = 0; i < words.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, words.length);
      final chunkWords = words.sublist(i, end);
      final chunkText = chunkWords.join(' ');
      if (chunkText.trim().isNotEmpty) {
        chunks.add(chunkText);
      }
    }

    print('[VectorDB] indexTextForBook: created ${chunks.length} chunks');

    // Insert chunks in small batches to avoid memory pressure and UI blocking
    var inserted = 0;
    const batchSize = 5;
    for (var batchStart = 0; batchStart < chunks.length; batchStart += batchSize) {
      try {
        final batchEnd = (batchStart + batchSize).clamp(0, chunks.length);
        final batch = chunks.sublist(batchStart, batchEnd);
        for (var idx = 0; idx < batch.length; idx++) {
          try {
            final chunkText = batch[idx];
            List<double>? emb;
            if (embedder != null) {
              try {
                emb = await embedder(chunkText);
              } catch (e) {
                print('[VectorDB] embedder failed for chunk ${batchStart + idx}: $e');
                emb = null;
              }
            }
            // Use chunk index as start/end page (placeholder)
            await insertChunk(bookId, batchStart + idx, batchStart + idx, chunkText, emb);
            inserted++;
          } catch (e) {
            print('[VectorDB] Failed to insert chunk ${batchStart + idx}: $e');
          }
        }
        print('[VectorDB] indexTextForBook batch: inserted ${batchStart + batch.length}/${chunks.length} chunks');
        // Yield to event loop to avoid blocking UI
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print('[VectorDB] Batch processing error: $e');
      }
    }

    print('[VectorDB] indexTextForBook complete: inserted=$inserted for book=$bookId');
    return inserted;
  }

  // Debug helper: print all stored QA pairs (id, book, question, has_embedding)
  static Future<void> dumpQaPairs() async {
    final db = await openDb();
    final rows = await db.rawQuery('SELECT id, book, question, answer, question_embedding IS NOT NULL as has_embedding FROM qa_pairs ORDER BY id DESC');
    print('[VectorDB] dumpQaPairs count=${rows.length}');
    for (var r in rows) {
      final q = (r['question'] ?? '').toString();
      final a = (r['answer'] ?? '').toString();
      // attempt to fetch embedding length
      int embLen = 0;
      try {
        final dbRow = await db.rawQuery('SELECT length(question_embedding) as b FROM qa_pairs WHERE id = ?', [r['id']]);
        if (dbRow.isNotEmpty) {
          final b = dbRow.first['b'] as int? ?? 0;
          embLen = b ~/ 8;
        }
      } catch (_) {}
      print('  qa id=${r['id']} book=${r['book']} hasEmbedding=${r['has_embedding']} embLen=$embLen question=${q.substring(0, math.min(80, q.length))} answer=${a.substring(0, math.min(120, a.length))}');
    }
  }

  // Debug helper: print all cached query embedding keys and their vector lengths
  static Future<void> dumpQueryEmbeddings() async {
    final db = await openDb();
    final rows = await db.rawQuery('SELECT query, length(embedding) as bytes FROM query_embeddings');
    print('[VectorDB] dumpQueryEmbeddings count=${rows.length}');
    for (var r in rows) {
      final key = r['query'];
      final bytes = r['bytes'] as int? ?? 0;
      final len = bytes ~/ 8;
      print('  key=$key len=$len bytes=$bytes');
    }
  }

  // Migration helper: clean previously-saved QA answers that begin with
  // machine-readable 'NOT FOUND' prefixes so stored answers are user-friendly.
  static Future<int> migrateCleanNotFoundAnswers() async {
    final db = await openDb();
    final rows = await db.rawQuery('SELECT id, answer FROM qa_pairs');
    var updated = 0;
    for (var r in rows) {
      try {
        final id = r['id'] as int?;
        var ans = (r['answer'] ?? '').toString();
        final low = ans.toLowerCase();
        var cleaned = ans;
        var skip = false;
        if (low.startsWith('not found in books:')) {
          cleaned = ans.substring('not found in books:'.length).trim();
        } else if (low.startsWith('not found in book:')) {
          cleaned = ans.substring('not found in book:'.length).trim();
        } else if (low.contains('no relevant information found in the selected book')) {
          // This indicates there was nothing to save; remove the entry.
          if (id != null) {
            await db.delete('qa_pairs', where: 'id = ?', whereArgs: [id]);
            updated++;
          }
          skip = true;
        }
        if (!skip && cleaned != ans && (id != null)) {
          await db.update('qa_pairs', {'answer': cleaned}, where: 'id = ?', whereArgs: [id]);
          updated++;
        }
      } catch (_) {}
    }
    print('[VectorDB] migrateCleanNotFoundAnswers updated=$updated');
    return updated;
  }

  // Debug smoke test: insert a QA then run answerQuery for the same text to show retrieval
  static Future<void> smokeTestInsertAndQuery(String book, String question, String answer) async {
    print('[VectorDB] smokeTest: inserting QA...');
    await insertQaPair(book, question, answer, null);
    print('[VectorDB] smokeTest: querying...');
    final res = await answerQuery(question, topK: 5, book: book);
    print('[VectorDB] smokeTest: got ${res.length} results');
    for (var r in res) {
      print('  res source=${r['source']} score=${r['score']} question=${r['question'] ?? ''} answer=${r['answer'] ?? ''}');
    }
  }

  // Insert a synthetic Q/A pair (optionally with an embedding for the question)
  static Future<int> insertQaPair(String book, String question, String answer, List<double>? questionEmbedding) async {
    final db = await openDb();
    // Do not insert empty answers — central guard to avoid question-only rows
    String cleanedAnswer = (answer ?? '').toString();
    try {
      // Remove common 'not found' prefixes so saved answers don't include
      // short machine-readable markers like "NOT FOUND IN BOOKS:.".
      try {
        final low = cleanedAnswer.toLowerCase();
        if (low.startsWith('not found in books:')) {
          cleanedAnswer = cleanedAnswer.substring('not found in books:'.length).trim();
        } else if (low.startsWith('no relevant information found in the selected book')) {
          // treat this as empty (nothing to save)
          print('[VectorDB] insertQaPair skipped: book reported no relevant info for questionKey="${normalizeKey(question)}" book="$book"');
          return -1;
        } else if (low.startsWith('not found in book:')) {
          cleanedAnswer = cleanedAnswer.substring('not found in book:'.length).trim();
        }
      } catch (_) {}
      if (cleanedAnswer.trim().isEmpty) {
        print('[VectorDB] insertQaPair skipped: empty answer for questionKey="${normalizeKey(question)}" book="$book"');
        return -1;
      }
    } catch (_) {}
    Uint8List? embBytes;
    if (questionEmbedding != null) {
      embBytes = _doubleListToByteData(questionEmbedding).buffer.asUint8List();
    }
  final bookId = normalizeBookId(book);
  final id = await db.insert('qa_pairs', {'book': bookId, 'question': question, 'answer': cleanedAnswer, 'question_embedding': embBytes, 'unsynced': 1});
  // Debug: log insert and embedding length
  var embLen = 0;
  if (embBytes != null) embLen = embBytes.lengthInBytes ~/ 8;
  // Print inserted QA with trimmed question/answer to the terminal for debugging
  try {
    final qPreview = question.length > 400 ? '${question.substring(0, 400)}...' : question;
    final aPreview = answer.length > 800 ? '${answer.substring(0, 800)}...' : answer;
    print('[VectorDB] insertQaPair id=$id book="$book" embedded=${questionEmbedding != null} embLen=$embLen');
    print('  QUESTION: $qPreview');
    print('  ANSWER: $aPreview');
  } catch (_) {
    print('[VectorDB] insertQaPair id=$id book="$book" embedded=${questionEmbedding != null} embLen=$embLen (could not print full text)');
  }
    // Also cache the normalized question embedding for quick query lookup
    try {
      if (questionEmbedding != null) {
        final norm = normalizeKey(question);
        await insertQueryEmbedding(norm, questionEmbedding);
      }
    } catch (_) {}
    // Final confirmation: report whether the question embedding was cached
    try {
      if (questionEmbedding != null) {
        final norm = normalizeKey(question);
        final cached = await queryEmbedding(norm);
        if (cached != null) {
          print('[VectorDB][SavedOK] id=$id book="$book" embedded=true embLen=${cached.length} key="$norm"');
        } else {
          print('[VectorDB][SavedOK] id=$id book="$book" embedded=true embLen=${embLen} key="$norm" (cache readback failed)');
        }
      } else {
        print('[VectorDB][SavedOK] id=$id book="$book" embedded=false');
      }
    } catch (_) {
      print('[VectorDB][SavedOK] id=$id book="$book" embedded=${questionEmbedding != null} (post-check failed)');
    }

    return id;
  }

  // Simple text-based search across stored QA questions (fallback when embeddings aren't available).
  static Future<List<Map<String, dynamic>>> searchQaPairsByText(String query, {String? book, int topK = 5}) async {
    final db = await openDb();
    final where = (book != null) ? 'WHERE book = ?' : '';
    final bookId = book != null ? normalizeBookId(book) : null;
    final rows = await db.rawQuery('SELECT id, book, question, answer, question_embedding FROM qa_pairs $where', bookId != null ? [bookId] : []);
    // Normalize query text for more consistent tokenization
  final normQuery = normalizeKey(query);
    final qterms = normQuery.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final scored = <Map<String, dynamic>>[];
    for (var r in rows) {
      try {
  final text = "${(r['question'] ?? '').toString().toLowerCase()} ${(r['answer'] ?? '').toString().toLowerCase()}";
        var count = 0;
        for (var t in qterms) {
          final re = RegExp(RegExp.escape(t), caseSensitive: false);
          count += re.allMatches(text).length;
        }
        scored.add({'score': count.toDouble(), 'row': r});
      } catch (_) {}
    }
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scored.take(topK).map((s) => s['row'] as Map<String, dynamic>).toList();
  }

  // Public helper: convert a little-endian Float64 byte blob into a Float64List
  static Float64List byteDataToDoubleList(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    final list = Float64List(byteData.lengthInBytes ~/ 8);
    for (var i = 0; i < list.length; i++) {
      list[i] = byteData.getFloat64(i * 8, Endian.little);
    }
    return list;
  }

  static ByteData _doubleListToByteData(List<double> values) {
    final bd = ByteData(values.length * 8);
    for (var i = 0; i < values.length; i++) {
      bd.setFloat64(i * 8, values[i], Endian.little);
    }
    return bd;
  }

  // Store a cached embedding for a query (replace if exists)
  static Future<void> insertQueryEmbedding(String query, List<double> embedding) async {
    final db = await openDb();
  final key = normalizeKey(query);
    final embBytes = _doubleListToByteData(embedding).buffer.asUint8List();
    await db.insert('query_embeddings', {'query': key, 'embedding': embBytes}, conflictAlgorithm: ConflictAlgorithm.replace);
    print('[VectorDB] insertQueryEmbedding key="$key" len=${embedding.length}');
  }

  // Retrieve a cached embedding for a query, or null if not found
  static Future<List<double>?> queryEmbedding(String query) async {
    final db = await openDb();
  final key = normalizeKey(query);
    final rows = await db.query('query_embeddings', where: 'query = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final embBytes = rows.first['embedding'] as Uint8List;
    final fl = byteDataToDoubleList(embBytes);
    print('[VectorDB] queryEmbedding found key="$key" len=${fl.length}');
    return List<double>.from(fl);
  }

  // Normalize keys/queries for stable caching and lookup
  static String normalizeKey(String input) {
    var s = input.trim().toLowerCase();
    // Replace non-alphanumeric characters with spaces
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    // Collapse multiple spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  // Normalize a book identifier to a canonical base name (strip path and extension)
  static String normalizeBookId(String book) {
    try {
      var b = book.toString();
      // Take basename if a path was passed
      b = p.basename(b);
      final dot = b.lastIndexOf('.');
      if (dot > 0) b = b.substring(0, dot);
      return b;
    } catch (_) {
      return book;
    }
  }

  // --- Similarity helpers -------------------------------------------------
  static double _dot(List<double> a, List<double> b) {
    final len = math.min(a.length, b.length);
    var sum = 0.0;
    for (var i = 0; i < len; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static double _norm(List<double> a) {
    var sum = 0.0;
    for (var v in a) {
      sum += v * v;
    }
    return math.sqrt(sum);
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na == 0 || nb == 0) return 0.0;
    return _dot(a, b) / (na * nb);
  }

  // --- Nearest-neighbour search ------------------------------------------
  // Return top-K chunk rows augmented with a 'score' field (cosine similarity)
  static Future<List<Map<String, dynamic>>> topKChunksByEmbedding(List<double> queryEmbedding, {int topK = 5, String? book}) async {
    final db = await openDb();
    final where = (book != null) ? 'WHERE c.book = ?' : '';
    final bookId = book != null ? normalizeBookId(book) : null;
    final rows = await db.rawQuery('SELECT c.id, c.book, c.start_page, c.end_page, c.text, e.embedding FROM chunks c JOIN embeddings e ON c.id = e.chunk_id $where', bookId != null ? [bookId] : []);
    final scored = <Map<String, dynamic>>[];
    for (var r in rows) {
      try {
        final embBytes = r['embedding'] as Uint8List;
        final emb = byteDataToDoubleList(embBytes);
        final score = _cosineSimilarity(queryEmbedding, List<double>.from(emb));
        final out = Map<String, dynamic>.from(r);
        out['score'] = score;
        out['source'] = 'chunk';
        scored.add(out);
      } catch (_) {}
    }
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scored.take(topK).toList();
  }

  // Return top-K QA rows augmented with a 'score' field
  static Future<List<Map<String, dynamic>>> topKQaByEmbedding(List<double> queryEmbedding, {int topK = 5, String? book}) async {
    final db = await openDb();
    final where = (book != null) ? 'WHERE book = ?' : '';
  final bookId = book != null ? normalizeBookId(book) : null;
  final rows = await db.rawQuery('SELECT id, book, question, answer, question_embedding FROM qa_pairs $where', bookId != null ? [bookId] : []);
    final scored = <Map<String, dynamic>>[];
    for (var r in rows) {
      try {
        final embBytes = r['question_embedding'] as Uint8List?;
        if (embBytes == null) continue;
        final emb = byteDataToDoubleList(embBytes);
        final score = _cosineSimilarity(queryEmbedding, List<double>.from(emb));
        final out = Map<String, dynamic>.from(r);
        out['score'] = score;
        out['source'] = 'qa';
        scored.add(out);
      } catch (_) {}
    }
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scored.take(topK).toList();
  }

  // Train offline from a list of QA maps. Each map should contain: 'book', 'question', 'answer', and optionally 'question_embedding' as List<double>.
  static Future<void> trainOfflineFromList(List<Map<String, dynamic>> items) async {
    final db = await openDb();
    print('[VectorDB] trainOfflineFromList: count=${items.length}');
    await db.transaction((txn) async {
      for (var it in items) {
        final book = normalizeBookId(it['book']?.toString() ?? '');
        final question = it['question']?.toString() ?? '';
        final answer = it['answer']?.toString() ?? '';
        final embedding = it['question_embedding'] as List<double>?;
        // skip blank questions or answers
        if (question.trim().isEmpty || answer.trim().isEmpty) {
          print('[VectorDB] trainOfflineFromList skipped empty item book="$book" questionKey="${normalizeKey(question)}"');
          continue;
        }
        if (embedding != null) {
          final embBytes = _doubleListToByteData(embedding).buffer.asUint8List();
          final id = await txn.insert('qa_pairs', {'book': book, 'question': question, 'answer': answer, 'question_embedding': embBytes, 'unsynced': 0});
          final key = normalizeKey(question);
            await txn.insert('query_embeddings', {'query': key, 'embedding': embBytes}, conflictAlgorithm: ConflictAlgorithm.replace);
          print('[VectorDB] trainOffline inserted id=$id book="$book" key="$key"');
        } else {
          final id = await txn.insert('qa_pairs', {'book': book, 'question': question, 'answer': answer, 'question_embedding': null, 'unsynced': 0});
          print('[VectorDB] trainOffline inserted id=$id book="$book" key="${normalizeKey(question)}" embedded=false');
        }
      }
    });
  }

  // Unified query answering helper. Prefers cached query embedding, then an optional embedder callback, then text fallback.
  // Returns a merged, score-sorted list of results where each item has: 'source' ('qa'|'chunk'), 'score', and the original row fields.
  static Future<List<Map<String, dynamic>>> answerQuery(String query, {List<double>? embedding, Future<List<double>> Function(String)? embedder, int topK = 5, String? book}) async {
    // Prefer provided embedding -> cached embedding -> embedder -> text fallback
    var emb = embedding;
    // Try cached embedding first; use null-aware assignment for clarity.
    emb ??= await queryEmbedding(query);
    if (emb == null && embedder != null) {
      try {
        final embFrom = await embedder(query); // embedder returns non-null List<double>
        emb = embFrom;
        await insertQueryEmbedding(query, embFrom);
      } catch (_) {
        // leave emb as null
      }
    }

    if (emb != null) {
      final qaResults = await topKQaByEmbedding(emb, topK: topK, book: book);
      final chunkResults = await topKChunksByEmbedding(emb, topK: topK, book: book);
      final merged = <Map<String, dynamic>>[];
      merged.addAll(qaResults);
      merged.addAll(chunkResults);
      merged.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      // Deduplicate very similar/identical answers so the caller doesn't repeatedly
      // receive the same text for different queries. Use a normalized answer/text
      // fingerprint to detect duplicates and also filter out extremely low scores.
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (var item in merged) {
        try {
          final src = (item['source'] ?? 'qa').toString();
          String txt = '';
          if (src == 'qa') {
            txt = (item['answer'] ?? item['question'] ?? '').toString();
          } else {
            txt = (item['text'] ?? item['excerpt'] ?? '').toString();
          }
          final fingerprint = normalizeKey(txt);
          // Skip duplicate textual content
          if (fingerprint.isEmpty || seen.contains(fingerprint)) continue;
          // Skip extremely low-scoring matches (likely noise)
          final score = (item['score'] as double?) ?? 0.0;
          if (score <= 0.01) continue;
          seen.add(fingerprint);
          deduped.add(item);
        } catch (_) {
          // If anything goes wrong, keep the item (best-effort)
          deduped.add(item);
        }
      }

      return deduped.take(topK).toList();
    }

    // Fallback to text-based QA search
    var textRows = await searchQaPairsByText(query, book: book, topK: topK);
    // If nothing found within the specific book scope, try a global search as a fallback
    if ((textRows.isEmpty) && (book != null)) {
      try {
        textRows = await searchQaPairsByText(query, book: null, topK: topK);
      } catch (_) {}
    }
    // Normalize to the same output shape
    final out = textRows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['score'] = 0.0;
      m['source'] = 'qa';
      return m;
    }).toList();
    return out;
  }
}
