// ignore_for_file: avoid_print

import 'dart:math';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'vector_db.dart';
import 'embedding_service.dart';

class RagService {
  final EmbeddingService embeddingService;
  // Last parsed citations from the most recent answerWithOpenAI call.
  List<Map<String, dynamic>> lastCitations = [];
  // Last parsed short bullet summary from the most recent answerWithOpenAI call.
  List<String> lastBullets = [];
  RagService(this.embeddingService);

  // cosine similarity between two vectors
  double _cosine(List<double> a, List<double> b) {
    double da = 0, db = 0, dot = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      da += a[i] * a[i];
      db += b[i] * b[i];
    }
    return dot / (sqrt(da) * sqrt(db) + 1e-12);
  }

  Future<List<Map<String, dynamic>>> retrieve(String query, {int topK = 5, String? book}) async {
    List<double>? qEmb;

    // Try to load a cached embedding for this exact query
    try {
      qEmb = await VectorDB.queryEmbedding(query);
    } catch (_) {
      qEmb = null;
    }

    // If not cached, try to compute via the embedding service (may fail if offline)
    if (qEmb == null) {
      try {
        qEmb = await embeddingService.embedText(query);
        // Persist for offline reuse
        try {
          await VectorDB.insertQueryEmbedding(query, qEmb);
        } catch (_) {}
      } catch (_) {
        // embedding unavailable (likely offline) -> fall back to keyword matching below
        qEmb = null;
      }
    }

    // Load rows, optionally scoped to a book
    final rows = (book != null) ? await VectorDB.chunksForBook(book) : await VectorDB.allChunks();
    final scored = <Map<String, dynamic>>[];
    for (var r in rows) {
      try {
        final embBytes = r['embedding'] as List<int>;
        final emb = VectorDB.byteDataToDoubleList(Uint8List.fromList(embBytes));
        double score;
        if (qEmb != null) {
          try {
            score = _cosine(qEmb, emb);
          } catch (_) {
            score = 0.0;
          }
        } else {
          // Fallback: simple token-frequency match score when embeddings aren't available
          final text = (r['text'] ?? '').toString().toLowerCase();
          final qterms = query.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          var count = 0;
          for (var t in qterms) {
            final re = RegExp(RegExp.escape(t), caseSensitive: false);
            count += re.allMatches(text).length;
          }
          score = count.toDouble();
        }
        scored.add({'score': score, 'chunk': r});
      } catch (_) {}
    }
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final out = scored.take(topK).toList();
    // Verbose debug logging: show topK chunk previews and scores
    try {
      print('[RagService][Retrieve] query="${query}" book=${book ?? '<all>'} topK=${out.length}');
      for (var i = 0; i < out.length; i++) {
        try {
          final s = (out[i]['score'] as num?)?.toDouble() ?? 0.0;
          final ch = out[i]['chunk'];
          final txt = (ch['text'] ?? '').toString();
          final preview = txt.length > 200 ? txt.substring(0, 200) + '...' : txt;
          print('  #${i + 1} score=${s.toStringAsFixed(4)} book=${ch['book']} preview=${preview}');
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

    Future<Map<String, dynamic>> answerWithOpenAI(
      String question, List<Map<String, dynamic>> chunks, String apiKey) async {
    // Build a stricter prompt that requests a concise answer and a JSON
    // object with 'answer' and 'citations' so the client can display
    // which passages were used. This helps avoid ambiguous or off-topic
    // replies that just dump excerpts.
    final sb = StringBuffer();
    // Determine if the provided chunks reference a single book so we can
    // instruct the model to strictly restrict its answer to that book.
    String? requestedBook;
    if (chunks.isNotEmpty) {
      final first = chunks[0]['chunk'];
      if (first != null && first['book'] != null) requestedBook = first['book'].toString();
    }

    sb.writeln(
      'You are a helpful assistant. Use ONLY the following excerpts from books to answer the question whenever they contain the answer. Provide a concise answer (1-4 sentences).');
    sb.writeln('\nFormatting/style: Provide a polished, user-friendly answer that is easy to read — you may rephrase and "spice" the language for clarity and tone (use natural, conversational phrasing and short paragraphs), but do NOT add facts or information that are not present in the supplied excerpts. Keep the answer grounded in evidence from the excerpts.');
    if (requestedBook != null && requestedBook.isNotEmpty) {
      sb.writeln('\nIMPORTANT: The user has requested answers from a specific book: "$requestedBook".');
      sb.writeln('You MUST use only the supplied excerpts from this book to answer. Do NOT use any external knowledge or other books.');
      sb.writeln('If the supplied excerpts do NOT contain the answer, return EXACTLY the sentence: "No relevant information found in the selected book." as the value of the "answer" field, and set "citations" to an empty array.');
    }
    sb.writeln('\nIMPORTANT: Return ONLY a single valid JSON object (no surrounding commentary) with the following keys:\n - "answer": a concise answer string (1 paragraph),\n - "bullets": an array of up to 3 short bullet points that summarize the answer (each 6-18 words),\n - "citations": an array of objects each with keys {"book","page","chunk_index","quote"} representing evidence used.');
    sb.writeln('\nIf the excerpts do NOT contain the answer, return a JSON object with "answer" starting with "NOT FOUND IN BOOKS:" followed by a brief general-answer, an empty "citations" array, and an optional "bullets" array.');
    sb.writeln('\nExcerpts:');
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      final chunk = c['chunk'];
      final book = chunk['book']?.toString() ?? '';
      final start = chunk['start_page']?.toString() ?? '';
      final end = chunk['end_page']?.toString() ?? '';
      final text = (chunk['text'] ?? '').toString();
      sb.writeln('\n---\n#CHUNK_INDEX:$i');
      sb.writeln('Book: $book Pages: $start-$end');
      sb.writeln(text);
    }
    sb.writeln('\nQuestion: $question');

    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'messages': [
        {
          'role': 'system',
          'content': 'You are a concise, evidence-first assistant that MUST return a single JSON object as described by the user message. Do not include any extra commentary outside the JSON.'
        },
        {'role': 'user', 'content': sb.toString()},
      ],
      'temperature': 0.0,
      'max_tokens': 600,
    });
    // Try a few times for transient network or OpenAI hiccups
    http.Response? res;
    String? errBody;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        res = await http.post(url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey'
            },
            body: body).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) break;
        errBody = res.body;
        // short backoff
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      } on SocketException catch (e) {
        errBody = e.toString();
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      } catch (e) {
        errBody = e.toString();
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      }
    }

    if (res == null) {
      print('[RagService][ERROR] No HTTP response from OpenAI after retries. lastError=$errBody');
      throw Exception('No response from OpenAI: $errBody');
    }
    if (res.statusCode != 200) {
      print('[RagService][ERROR] OpenAI returned status=${res.statusCode} body=${res.body}');
      throw Exception('OpenAI failed: ${res.statusCode} ${res.body}');
    }

    Map<String, dynamic> decoded = {};
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      print('[RagService][ERROR] Failed to decode OpenAI response JSON: ${e.toString()} body=${res.body}');
      throw Exception('OpenAI response parse error: $e');
    }

    final content = decoded['choices']?[0]?['message']?['content'] as String? ?? '';
    final raw = content.trim();
    String answer = raw;
    // Reset lastCitations / lastBullets
    lastCitations = [];
    lastBullets = [];
    // Try to extract a JSON object from the model output
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        final jsonStr = raw.substring(start, end + 1);
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (parsed.containsKey('answer')) {
          answer = (parsed['answer'] ?? '').toString();
        }
        if (parsed.containsKey('citations') && parsed['citations'] is List) {
          final List cit = parsed['citations'] as List;
          for (var c in cit) {
            try {
              final m = Map<String, dynamic>.from(c as Map);
              lastCitations.add(m);
            } catch (_) {}
          }
        }
        if (parsed.containsKey('bullets') && parsed['bullets'] is List) {
          final List b = parsed['bullets'] as List;
          for (var it in b) {
            try {
              final s = it?.toString() ?? '';
              if (s.trim().isNotEmpty) lastBullets.add(s.trim());
            } catch (_) {}
          }
        }
      } else {
        // No JSON found — attempt a lightweight heuristic: if raw begins with 'NOT FOUND IN BOOKS', keep as-is and no citations
        if (raw.toUpperCase().startsWith('NOT FOUND IN BOOKS')) {
          answer = raw;
          lastCitations = [];
        } else {
          // As a fallback, try to construct simple citations from the provided chunks by choosing top ones
          final cnt = math.min(3, chunks.length);
          for (var i = 0; i < cnt; i++) {
            try {
              final ch = chunks[i]['chunk'];
              final quote = (ch['text'] ?? '').toString();
              lastCitations.add({
                'book': ch['book'] ?? '',
                'page': ch['start_page'] ?? null,
                'chunk_index': i,
                'quote': quote.length > 300 ? quote.substring(0, 300) + '...' : quote
              });
            } catch (_) {}
          }
          // As a minimal fallback for bullets, create short summaries using the first 1-2 chunks
          try {
            for (var i = 0; i < math.min(2, chunks.length); i++) {
              final ch = chunks[i]['chunk'];
              final text = (ch['text'] ?? '').toString();
              if (text.isNotEmpty) {
                final s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
                lastBullets.add(s.length > 80 ? s.substring(0, 80) + '...' : s);
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      print('[RagService] Failed to parse structured answer: $e');
      // fallback: set no citations and return raw
      lastCitations = [];
      answer = raw;
    }

      // If a specific book was requested, validate that any parsed citations
      // actually reference that book. If not, treat as "no relevant info".
      try {
        if (requestedBook != null && requestedBook.isNotEmpty) {
          var hasMatching = false;
          for (var c in lastCitations) {
            try {
              final b = (c['book'] ?? '').toString();
              if (b.isNotEmpty && b == requestedBook) {
                hasMatching = true;
                break;
              }
            } catch (_) {}
          }
          if (!hasMatching) {
            // Enforce the strict book-only response
            answer = 'No relevant information found in the selected book.';
            lastCitations = [];
            lastBullets = [];
          }
        }
      } catch (_) {}

    // Persist the QA pair for offline use. Use the first chunk's book if available.
    try {
      String bookId = '';
      if (chunks.isNotEmpty) {
        final first = chunks[0]['chunk'];
        if (first != null && first['book'] != null) bookId = first['book'].toString();
      }
      try {
        print('[RagService][SaveAttempt] Q: "$question"');
        print('[RagService][SaveAttempt] A: "${answer}"');
        if (answer.trim().isNotEmpty) {
          try {
            final qEmb = await embeddingService.embedText(question);
            await VectorDB.insertQaPair(bookId, question, answer, qEmb);
            print('[RagService] Cached QA for questionKey="${VectorDB.normalizeKey(question)}" book="$bookId"');
          } catch (_) {
            // If embedding fails (offline or error), still store QA pair without embedding
            try {
              await VectorDB.insertQaPair(bookId, question, answer, null);
              print('[RagService] Cached QA (without embedding) for questionKey="${VectorDB.normalizeKey(question)}" book="$bookId"');
            } catch (_) {}
          }
        } else {
          print('[RagService][Skip] Not saving QA because answer is empty for Q: "$question"');
        }
      } catch (_) {}
    } catch (_) {}

    // Return a structured Map so callers can consume answer, bullets and citations
    return {
      'answer': answer,
      'bullets': lastBullets,
      'citations': lastCitations,
      'raw': raw,
    };
  }

  // Improved offline answer
  Future<String> answerOffline(
      String question, List<Map<String, dynamic>> chunks) async {
    // Prefer semantic cached answers (QA) or chunk-level similarity via VectorDB
    try {
      // Determine a book scope if the provided chunks reference one
      String? book;
      if (chunks.isNotEmpty) {
        final first = chunks[0]['chunk'];
        if (first != null && first['book'] != null) book = first['book'].toString();
      }

      final results = await VectorDB.answerQuery(question, embedder: embeddingService.embedText, topK: 6, book: book);
      if (results.isNotEmpty) {
        final top = results.first;
        // If the top result is a stored QA pair, return its answer directly
        if (top['source'] == 'qa' && top.containsKey('answer')) {
          return (top['answer'] ?? '').toString();
        }

        // Otherwise, assemble a summary from the top chunk results
        final chunkItems = results.where((r) => r['source'] == 'chunk').toList();
        if (chunkItems.isNotEmpty) {
          final sb = StringBuffer();
          sb.writeln("Here’s what I found related to your question:\n");
          for (var c in chunkItems) {
            try {
              final book = c['book'] ?? 'Unknown';
              final start = c['start_page'] ?? '?';
              final end = c['end_page'] ?? start;
              final text = (c['text'] ?? '').toString();
              sb.writeln("📖 Book: $book (Pages $start–$end)");
              sb.writeln(text.length > 400 ? "${text.substring(0, 400)}..." : text);
              sb.writeln("\n---\n");
            } catch (_) {}
          }
          sb.writeln("\n⚠️ Note: This answer is generated offline from stored excerpts and may not be complete.");
          return sb.toString();
        }
      }
    } catch (_) {}

    // Fallback to the original chunk-based summary if the semantic search didn't help
    if (chunks.isEmpty) {
      return "Sorry, I couldn't find anything relevant in the offline books for your question.";
    }
    final sb = StringBuffer();
    sb.writeln("Here’s what I found related to your question:\n");
    for (var c in chunks) {
      try {
        final chunk = c['chunk'];
        final book = chunk['book'] ?? 'Unknown';
        final start = chunk['start_page'] ?? '?';
        final end = chunk['end_page'] ?? start;
        final text = (chunk['text'] ?? '').toString();
        sb.writeln("📖 Book: $book (Pages $start–$end)");
        sb.writeln(text.length > 400 ? "${text.substring(0, 400)}..." : text);
        sb.writeln("\n---\n");
      } catch (_) {}
    }
    sb.writeln("\n⚠️ Note: This answer is generated offline from the stored book excerpts and may not be complete.");
    return sb.toString();
  }

  // Train a book by generating synthetic Q/A pairs using OpenAI and storing them locally.
  // `bookId` should match the 'book' field used in chunks. `chunks` is a list of chunk rows.
  Future<void> trainBookWithOpenAI(String bookId, List<Map<String, dynamic>> chunks, String apiKey) async {
    // Send training requests in smaller batches to avoid huge request bodies
    // which can block the UI or hit request size/token limits.
    if (chunks.isEmpty) return;

    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    const int maxBatchChars = 20 * 1024; // ~20KB of text per batch (tunable)
    const int maxChunksPerBatch = 8; // fallback limit
    final batches = <List<Map<String, dynamic>>>[];

    // Group chunks into batches based on approximate serialized size
    var current = <Map<String, dynamic>>[];
    var curSize = 0;
    for (var c in chunks) {
      final chunk = c['chunk'];
      final text = (chunk['text'] ?? '').toString();
      final est = text.length + 200; // rough overhead per chunk
      if (current.length >= maxChunksPerBatch || (curSize + est) > maxBatchChars) {
        batches.add(current);
        current = <Map<String, dynamic>>[];
        curSize = 0;
      }
      current.add(c);
      curSize += est;
    }
    if (current.isNotEmpty) batches.add(current);

    for (var bi = 0; bi < batches.length; bi++) {
      final batch = batches[bi];
      final sb = StringBuffer();
      sb.writeln('Generate up to 12 concise question and answer pairs based on the following excerpts. Return a JSON array of objects with {"q":"...","a":"..."}.');
      sb.writeln('\nExcerpts:');
      for (var c in batch) {
        final chunk = c['chunk'];
        sb.writeln('\n---\nBook: ${chunk['book']} Pages: ${chunk['start_page']}-${chunk['end_page']}\n${chunk['text']}');
      }

      final body = jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'system', 'content': 'You are a helpful assistant that extracts Q/A pairs from text.'},
          {'role': 'user', 'content': sb.toString()}
        ],
        'temperature': 0.0,
        'max_tokens': 800
      });

      http.Response? res;
      String? lastErr;
      try {
        // Use a reasonable timeout and retry once on transient failures
        for (var attempt = 1; attempt <= 2; attempt++) {
          try {
            res = await http.post(url, headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey'
            }, body: body).timeout(const Duration(seconds: 30));
            if (res.statusCode == 200) break;
            lastErr = res.body;
            await Future.delayed(Duration(milliseconds: 200 * attempt));
          } catch (e) {
            lastErr = e.toString();
            if (attempt < 2) await Future.delayed(Duration(milliseconds: 200 * attempt));
          }
        }
      } catch (e) {
        lastErr = e.toString();
      }

      if (res == null) {
        print('[RagService][Train] No response for batch $bi: $lastErr');
        continue;
      }
      if (res.statusCode != 200) {
        print('[RagService][Train] OpenAI failed for batch $bi: ${res.statusCode} ${res.body}');
        continue;
      }

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final content = decoded['choices']?[0]?['message']?['content'] as String? ?? '';

      // Try to parse JSON out of the completion text
      List<dynamic> pairs = [];
      try {
        pairs = jsonDecode(content) as List<dynamic>;
      } catch (e) {
        final start = content.indexOf('[');
        final end = content.lastIndexOf(']');
        if (start >= 0 && end > start) {
          try {
            pairs = jsonDecode(content.substring(start, end + 1)) as List<dynamic>;
          } catch (_) {}
        }
      }

      for (var p in pairs) {
        try {
          final q = (p['q'] ?? p['question'] ?? '').toString();
          final a = (p['a'] ?? p['answer'] ?? '').toString();
          if (q.trim().isEmpty || a.trim().isEmpty) continue;
          try {
            final qEmb = await embeddingService.embedText(q);
            await VectorDB.insertQaPair(bookId, q, a, qEmb);
          } catch (_) {
            await VectorDB.insertQaPair(bookId, q, a, null);
          }
        } catch (_) {}
      }

      // small delay to yield to the event loop and avoid overwhelming local DB / network
      try {
        await Future.delayed(const Duration(milliseconds: 120));
      } catch (_) {}
    }
  }

  // Try to answer a question offline using stored QA pairs.
  // It will prefer semantic matches using question embeddings when available, otherwise fall back to text-match.
  Future<String?> answerOfflineUsingQa(String question, {String? book}) async {
    // Use the unified VectorDB.search (semantic-first) to find stored QA answers
    try {
      final results = await VectorDB.answerQuery(question, embedder: embeddingService.embedText, topK: 6, book: book);
      if (results.isNotEmpty) {
        final top = results.first;
        if (top['source'] == 'qa' && top.containsKey('answer')) {
          return (top['answer'] ?? '').toString();
        }
      }
    } catch (_) {}
    return null;
  }
}