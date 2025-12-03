// ignore_for_file: avoid_print

import 'dart:math';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'vector_db.dart';
import 'embedding_service.dart';
import 'backend_client.dart';
import 'tasha_utils.dart';

class RagService {
  final EmbeddingService embeddingService;
  final BackendClient backend;
  
  List<Map<String, dynamic>> lastCitations = [];
  List<String> lastBullets = [];
  
  RagService(this.embeddingService, this.backend);

  // Cosine similarity between two vectors
  double _cosine(List<double> a, List<double> b) {
    double da = 0, db = 0, dot = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      da += a[i] * a[i];
      db += b[i] * b[i];
    }
    return dot / (sqrt(da) * sqrt(db) + 1e-12);
  }

  // Attempt to heuristically extract an author name from book text
  String _extractAuthorFromText(String text) {
    try {
      final head = text.length > 2000 ? text.substring(0, 2000) : text;
      // Look for common patterns
      final lines = head.split(RegExp(r'\r?\n'));
      for (var i = 0; i < min(12, lines.length); i++) {
        final l = lines[i].trim();
        if (l.isEmpty) continue;
        final lower = l.toLowerCase();
        if (lower.startsWith('author:') || lower.startsWith('authors:')) {
          return l.split(':').sublist(1).join(':').trim();
        }
        if (lower.startsWith('by ')) {
          return l.substring(3).trim();
        }
        if (lower.contains('written by')) {
          final m = RegExp(r'written by\s+(.+)', caseSensitive: false).firstMatch(l);
          if (m != null) return m.group(1)?.trim() ?? '';
        }
      }
      // If still not found, heuristically check the first 3 non-empty lines for a name-like line
      final nonEmpty = lines.where((s) => s.trim().isNotEmpty).take(6).toList();
      if (nonEmpty.length >= 2) {
        final candidate = nonEmpty[1].trim();
        if (RegExp(r'^[A-Z][a-z]+\s+[A-Z][a-z]+').hasMatch(candidate)) return candidate;
      }
    } catch (_) {}
    return '';
  }

  // Helper to append a batch summary record
  void _addBatchSummary(List<Map<String, dynamic>> acc, String summary, List<Map<String, dynamic>> batch) {
    String source = 'batch';
    try {
      if (batch.isNotEmpty) {
        final first = batch.first;
        final book = (first['chunk'] != null && first['chunk'] is Map) ? (first['chunk']['book'] ?? first['book']) : (first['book'] ?? 'batch');
        source = book?.toString() ?? 'batch';
      }
    } catch (_) {}
    acc.add({'summary': summary ?? '', 'source': source});
  }

  /// Retrieve top-K chunks for a query using embeddings or keyword matching
  Future<List<Map<String, dynamic>>> retrieve(String query, {int topK = 12, String? book}) async {
    List<double>? qEmb;

    try {
      qEmb = await VectorDB.queryEmbedding(query);
    } catch (_) {
      qEmb = null;
    }

    if (qEmb == null) {
      try {
        qEmb = await embeddingService.embedText(query);
        try {
          await VectorDB.insertQueryEmbedding(query, qEmb);
        } catch (_) {}
      } catch (_) {
        qEmb = null;
      }
    }

    final rows = (book != null) ? await VectorDB.chunksForBook(book) : await VectorDB.allChunks();
    final scored = <Map<String, dynamic>>[];
    
    for (var r in rows) {
      try {
        double score = 0.0;
        final embBytes = r['embedding'] as List<int>?;
        
        if (embBytes != null && embBytes.isNotEmpty && qEmb != null) {
          // If embedding exists and we have query embedding, use cosine similarity
          try {
            final emb = VectorDB.byteDataToDoubleList(Uint8List.fromList(embBytes));
            score = _cosine(qEmb, emb);
          } catch (_) {
            score = 0.0;
          }
        } else {
          // Fallback to text-based keyword matching (works for chunks without embeddings)
          final text = (r['text'] ?? '').toString().toLowerCase();
          final qterms = query.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          var count = 0;
          for (var t in qterms) {
            final re = RegExp(RegExp.escape(t), caseSensitive: false);
            count += re.allMatches(text).length;
          }
          score = count.toDouble();
        }
        
        if (score > 0) {
          scored.add({'score': score, 'chunk': r});
        }
      } catch (e) {
        print('[RagService][Retrieve] Error processing chunk: $e');
      }
    }
    
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final out = scored.take(topK).toList();
    
    try {
      print('[RagService][Retrieve] query="$query" book=${book ?? '<all>'} topK=${out.length}');
      for (var i = 0; i < out.length; i++) {
        try {
          final s = (out[i]['score'] as num?)?.toDouble() ?? 0.0;
          final ch = out[i]['chunk'];
          final txt = (ch['text'] ?? '').toString();
          final preview = txt.length > 200 ? txt.substring(0, 200) + '...' : txt;
          print('  #${i + 1} score=${s.toStringAsFixed(4)} book=${ch['book']} preview=$preview');
        } catch (_) {}
      }
    } catch (_) {}
    
    return out;
  }

  /// Answer a question using chunks via backend RAG endpoint
  Future<Map<String, dynamic>> answerWithOpenAI(
    String question, 
    List<Map<String, dynamic>> chunks, {
    String? apiKey,  // Optional: pass OpenAI key from app Settings
  }) async {
      print('[RagService] DEBUG: answerWithOpenAI called with apiKey = ${apiKey != null ? "YES (${apiKey.length} chars, first 10: ${apiKey.substring(0, 10)}...)" : "NO/NULL"}');
    try {
      // If no chunks were found, attempt fallbacks so we always return an answer
      if (chunks.isEmpty) {
        // 1) Try offline cached QA pairs
        try {
          // Try to find a cached QA match using the unified answerQuery helper
          final qres = await VectorDB.answerQuery(
            question,
            embedder: embeddingService.embedText,
            topK: 1,
          );
          if (qres.isNotEmpty) {
            final top = qres.first;
            if (top['source'] == 'qa' && (top['answer'] ?? '').toString().trim().isNotEmpty) {
              return {
                'answer': top['answer'].toString(),
                'bullets': <String>[],
                'citations': <Map<String, dynamic>>[],
                'confidence': (top['score'] as double?) ?? 0.6,
              };
            }
          }
        } catch (_) {}

        // 2) If a book context is available in the question or last used chunks metadata, try TXT fallback
        String? bookId;
        try {
          // Try to infer book id from question payload markers like "Using TXT: <book>" in UI
          final m = RegExp(r'Using TXT:\s*(.+)$', multiLine: true).firstMatch(question);
          if (m != null) bookId = m.group(1)?.trim();
        } catch (_) {}

        if (bookId != null && bookId.isNotEmpty) {
          try {
            final txt = await TashaUtils.loadTxtFallbackForBook(bookId);
            if (txt != null && txt.trim().isNotEmpty) {
              final ql = question.toLowerCase();
              // Author/title metadata detection
              if (ql.contains('author') || ql.contains('who wrote') || ql.contains('written by')) {
                final author = _extractAuthorFromText(txt);
                if (author.isNotEmpty) {
                  return {
                    'answer': 'Author: $author',
                    'bullets': <String>[],
                    'citations': <Map<String, dynamic>>[],
                    'confidence': 0.7,
                  };
                }
              }

              // For summary requests (e.g., "tell me about this book", "summarize"), ask backend to summarize using book text
              if (ql.contains('tell me about') || ql.contains('tell me about this book') || ql.contains('summar') || ql.contains('what is this book about')) {
                // Build a single synthetic chunk from the start of the book (up to a reasonable size)
                final preview = txt.length > 30000 ? txt.substring(0, 30000) : txt;
                final synth = [{'text': preview, 'book': bookId, 'start_page': '?', 'end_page': '?'}];
                try {
                  final res = await backend.ragAnswer(
                    question,
                    synth,
                    systemPrompt:
                        'You are a helpful assistant. Summarize the provided book excerpt and give a concise, useful summary of the book as a whole. If helpful, note likely topics covered.',
                    maxTokens: 600,
                    apiKey: apiKey,
                  );
                  return {
                    'answer': res['answer']?.toString() ?? '',
                    'bullets': <String>[],
                    'citations': <Map<String, dynamic>>[],
                    'confidence': res['confidence'] ?? 0.5,
                  };
                } catch (e) {
                  print('[RagService] Fallback summarize failed: $e');
                }
              }
            }
          } catch (e) {
            print('[RagService] TXT fallback load failed for book=$bookId: $e');
          }
        }

        // 3) Last-resort: call backend with a permissive system prompt so it can answer generally
        try {
          final synth = [
            {
              'text': 'NO_EXCERPTS_AVAILABLE: Provide a helpful, general answer to the question using background knowledge and common medical guidance when appropriate. Be clear when you are giving general information rather than quoting the book.',
              'book': 'no_excerpts',
              'start_page': '?',
              'end_page': '?'
            }
          ];
          final res = await backend.ragAnswer(
            question,
            synth,
            systemPrompt:
                'You are a helpful medical assistant. The provided excerpts note that no book excerpts are available; provide a useful, general answer to the user question. Do not invent book-specific facts, but give a practical, general summary or guidance based on common medical knowledge.',
            maxTokens: 700,
            apiKey: apiKey,
          );
          return {
            'answer': res['answer']?.toString() ?? '',
            'bullets': <String>[],
            'citations': <Map<String, dynamic>>[],
            'confidence': res['confidence'] ?? 0.5,
          };
        } catch (e) {
          print('[RagService] Final fallback failed: $e');
          return {
            'answer': 'I could not retrieve the book content and could not produce an answer right now. Try again later or save the book text for summarization.',
            'bullets': <String>[],
            'citations': <Map<String, dynamic>>[],
            'confidence': 0.2,
          };
        }
      }

      print('[RagService] Calling backend RAG for question: "${question}" chunks=${chunks.length}');

      // Normalize chunks into the flat shape backend expects: {text, book, start_page, end_page}
      final payloadChunks = <Map<String, dynamic>>[];
      for (var c in chunks) {
        try {
          final inner = (c is Map && c.containsKey('chunk')) ? (c['chunk'] as Map<String, dynamic>) : (c as Map<String, dynamic>);
          final text = (inner['text'] ?? inner['chunk'] ?? inner['content'] ?? '').toString();
          final book = (inner['book'] ?? inner['source'] ?? '').toString();
          final startPage = inner['start_page'] ?? inner['startPage'] ?? inner['start'] ?? '?';
          final endPage = inner['end_page'] ?? inner['endPage'] ?? inner['end'] ?? startPage;
          payloadChunks.add({
            'text': text,
            'book': book,
            'start_page': startPage,
            'end_page': endPage,
          });
        } catch (_) {
          // ignore malformed chunk
        }
      }

      // ✅ LOG CHUNKS BEING SENT TO OPENAI
      print('[RagService] ✅ NORMALIZED CHUNKS READY FOR OPENAI:');
      for (var i = 0; i < payloadChunks.length; i++) {
        final chunk = payloadChunks[i];
        final text = (chunk['text'] ?? '').toString();
        final preview = text.length > 150 ? text.substring(0, 150) + '...' : text;
        print('  Chunk[$i] book="${chunk['book']}" page=${chunk['start_page']} text_length=${text.length} preview="$preview"');
      }

      // Protective batching: if chunks total text size is very large, send in smaller batches
      final totalChars = payloadChunks.fold<int>(0, (p, c) {
        try {
          return p + (c['text'] ?? '').toString().length;
        } catch (_) {
          return p;
        }
      });
      
      print('[RagService] ✅ TOTAL TEXT CHARACTERS BEING SENT TO OPENAI: $totalChars chars (from ${payloadChunks.length} chunks)');

      const int MAX_DIRECT_CHARS = 30 * 1024; // 30 KB
      const int BATCH_CHARS = 18 * 1024; // ~18 KB per batch

      Map<String, dynamic> finalResult;

      if (totalChars <= MAX_DIRECT_CHARS) {
        // Small enough to send in one go
        print('[RagService] Sending all chunks in one request (totalChars=$totalChars)');
        finalResult = await backend.ragAnswer(
          question,
          payloadChunks,
          systemPrompt:
              'You are a helpful medical assistant. ALWAYS provide a comprehensive answer based on the excerpts. '
              'NEVER say "I cannot find" or "information is not available". Synthesize what IS in the excerpts. '
              'Provide detailed, thorough answers drawing from multiple excerpts where relevant. '
              'Include key medical points, treatments, recommendations, or relevant information. '
              'Aim for 3-8 sentences or more to fully address the question. '
              'Even if excerpts don\'t perfectly match, use related medical concepts to provide helpful context.',
          maxTokens: 1200,
          apiKey: apiKey,
        );
      } else {
        // Split into batches by approximate character size
        print('[RagService] Total chunk size $totalChars exceeds threshold; splitting into batches');
        final batches = <List<Map<String, dynamic>>>[];
        var current = <Map<String, dynamic>>[];
        var curSize = 0;
        for (var c in payloadChunks) {
          final txt = (c['text'] ?? '').toString();
          final len = txt.length + 200; // overhead
          if (curSize + len > BATCH_CHARS && current.isNotEmpty) {
            batches.add(current);
            current = <Map<String, dynamic>>[];
            curSize = 0;
          }
          current.add(c);
          curSize += len;
        }
        if (current.isNotEmpty) batches.add(current);

        print('[RagService] Split into ${batches.length} batches');

        // For each batch, ask backend for a short summary answer (keep it small)
        final batchSummaries = <Map<String, dynamic>>[];
        int idx = 0;
        for (var batch in batches) {
          idx++;
          try {
            print('[RagService] Sending batch $idx/${batches.length} with ${batch.length} chunks');
            final res = await backend.ragAnswer(
              question,
              batch,
              systemPrompt:
                  'You are a helpful medical assistant. ALWAYS provide a comprehensive answer. Never say "cannot find". Synthesize the provided excerpts to answer. Provide a detailed 2-4 sentence response drawing from multiple excerpts. Return plain text.',
              maxTokens: 500,
              apiKey: apiKey,
            );
            final ans = res['answer']?.toString() ?? '';
            _addBatchSummary(batchSummaries, ans, batch);
          } catch (e) {
            print('[RagService] Batch $idx failed: $e');
            // continue with what we have
            _addBatchSummary(batchSummaries, '', batch);
          }
        }

        // Build condensed chunks from batch summaries to form a final small request
        final condensed = <Map<String, dynamic>>[];
        for (var i = 0; i < batchSummaries.length; i++) {
          final s = batchSummaries[i]['summary'] as String? ?? '';
          final source = batchSummaries[i]['source'] as String? ?? 'batch${i + 1}';
          if (s.trim().isEmpty) continue;
          condensed.add({'text': s, 'book': source, 'start_page': '?', 'end_page': '?'});
        }

        if (condensed.isEmpty) {
          // If all batch summaries failed, fall back to sending a small subset (first N chunks)
          final fallback = payloadChunks.take(6).toList();
          print('[RagService] All summaries empty — falling back to first ${fallback.length} chunks');
          finalResult = await backend.ragAnswer(
            question,
            fallback,
            systemPrompt:
                'You are a helpful medical assistant. ALWAYS provide an answer. Never say cannot find information. Synthesize the excerpts to answer thoroughly. Include key medical information, treatments, recommendations. Aim for 3-8 sentences to fully address the question.',
            maxTokens: 1000,
            apiKey: apiKey,
          );
        } else {
          print('[RagService] Sending condensed ${condensed.length} summaries for final answer');
          finalResult = await backend.ragAnswer(
            question,
            condensed,
            systemPrompt:
                'You are a helpful medical assistant. ALWAYS provide a comprehensive answer. The following are summaries from medical excerpts. Synthesize them to provide a detailed answer. Include multiple relevant medical points. Never say information unavailable. Aim for 3-8 sentences or more.',
            maxTokens: 1200,
            apiKey: apiKey,
          );
        }
      }

      // Normalize finalResult to expected shape
      final answer = finalResult['answer']?.toString() ?? '';
      final citations = finalResult['citations'] as List<dynamic>? ?? [];
      final confidence = (finalResult['confidence'] as double?) ?? (finalResult['confidence'] is num ? (finalResult['confidence'] as num).toDouble() : 0.5);
      
      // Parse citations from the payloadChunks we sent
      lastCitations = [];
      for (var i = 0; i < payloadChunks.length; i++) {
        try {
          final chunk = payloadChunks[i];
          final quote = (chunk['text'] ?? '').toString();
          lastCitations.add({
            'book': chunk['book'] ?? '',
            'page': chunk['start_page'] ?? '?',
            'chunk_index': i,
            'quote': quote.length > 300 ? quote.substring(0, 300) + '...' : quote
          });
        } catch (_) {}
      }
      
      // Try to extract bullets from answer
      lastBullets = [];
      try {
        final lines = answer.split('\n');
        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('•') || trimmed.startsWith('-') || trimmed.startsWith('*')) {
            final bullet = trimmed.replaceFirst(RegExp(r'^[•\-*]\s*'), '').trim();
            if (bullet.isNotEmpty && bullet.length < 200) {
              lastBullets.add(bullet);
            }
          }
        }
      } catch (_) {}
      
      // Persist QA pair for offline use
      try {
        String bookId = '';
        if (chunks.isNotEmpty) {
          final first = chunks[0]['chunk'] as Map<String, dynamic>;
          if (first['book'] != null) bookId = first['book'].toString();
        }
        if (answer.trim().isNotEmpty) {
          try {
            final qEmb = await embeddingService.embedText(question);
            await VectorDB.insertQaPair(bookId, question, answer, qEmb);
          } catch (_) {
            try {
              await VectorDB.insertQaPair(bookId, question, answer, null);
            } catch (_) {}
          }
        }
      } catch (_) {}
      
      return {
        'answer': answer,
        'bullets': lastBullets,
        'citations': lastCitations,
        'confidence': confidence,
      };
    } catch (e) {
      print('[RagService] ERROR: $e');
      rethrow;
    }
  }

  /// Answer offline using cached QA pairs
  Future<String> answerOffline(String question, List<Map<String, dynamic>> chunks) async {
    try {
      String? book;
      if (chunks.isNotEmpty) {
        final first = chunks[0]['chunk'] as Map<String, dynamic>;
        if (first['book'] != null) book = first['book'].toString();
      }

      final results = await VectorDB.answerQuery(
        question, 
        embedder: embeddingService.embedText, 
        topK: 6, 
        book: book
      );
      
      if (results.isNotEmpty) {
        final top = results.first;
        if (top['source'] == 'qa' && top.containsKey('answer')) {
          return (top['answer'] ?? '').toString();
        }

        final chunkItems = results.where((r) => r['source'] == 'chunk').toList();
        if (chunkItems.isNotEmpty) {
          final sb = StringBuffer();
          sb.writeln("Here's what I found:\n");
          for (var c in chunkItems) {
            try {
              final book = c['book'] ?? 'Unknown';
              final start = c['start_page'] ?? '?';
              final end = c['end_page'] ?? start;
              final text = (c['text'] ?? '').toString();
              sb.writeln("📖 $book (Pages $start–$end)");
              sb.writeln(text.length > 400 ? "${text.substring(0, 400)}..." : text);
              sb.writeln("\n---\n");
            } catch (_) {}
          }
          sb.writeln("\n⚠️ Offline answer from stored excerpts.");
          return sb.toString();
        }
      }
    } catch (_) {}

    if (chunks.isEmpty) {
      return "Sorry, no offline data available for that question.";
    }
    
    final sb = StringBuffer();
    sb.writeln("Here's what I found:\n");
    for (var c in chunks) {
      try {
        final chunk = c['chunk'] as Map<String, dynamic>;
        final book = chunk['book'] ?? 'Unknown';
        final start = chunk['start_page'] ?? '?';
        final end = chunk['end_page'] ?? start;
        final text = (chunk['text'] ?? '').toString();
        sb.writeln("📖 $book (Pages $start–$end)");
        sb.writeln(text.length > 400 ? "${text.substring(0, 400)}..." : text);
        sb.writeln("\n---\n");
      } catch (_) {}
    }
    sb.writeln("\n⚠️ Offline answer from stored excerpts.");
    return sb.toString();
  }

  /// Train a book by generating Q/A pairs via backend
  Future<void> trainBookWithOpenAI(
    String bookId, 
    List<Map<String, dynamic>> chunks,
  ) async {
    if (chunks.isEmpty) return;

    try {
      print('[RagService] Training book=$bookId with ${chunks.length} chunks');
      
      final pairs = await backend.trainBook(bookId, chunks);
      
      print('[RagService] Generated ${pairs.length} Q/A pairs');
      
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
      
      print('[RagService] Training complete for book=$bookId');
    } catch (e) {
      print('[RagService] Training error: $e');
      rethrow;
    }
  }

  /// Answer offline using stored QA pairs
  Future<String?> answerOfflineUsingQa(String question, {String? book}) async {
    try {
      final results = await VectorDB.answerQuery(
        question, 
        embedder: embeddingService.embedText, 
        topK: 6, 
        book: book
      );
      
      if (results.isNotEmpty) {
        final top = results.first;
        if (top['source'] == 'qa' && top.containsKey('answer')) {
          return (top['answer'] ?? '').toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Format answer text for nice display: convert markdown-like formatting to clean text
  /// Converts **bold** to bold, *italic* to regular, - bullet points to nice format, etc.
  String formatAnswerForDisplay(String answer) {
    if (answer.isEmpty) return answer;
    
    try {
      var result = answer;
      
      // Clean up markdown bold (**text** → text, keeping the word)
      result = result.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), '\$1');
      
      // Clean up markdown italic (*text* → text)
      result = result.replaceAll(RegExp(r'\*([^*]+)\*'), '\$1');
      
      // Clean up other markdown artifacts (__text__, ~~text~~)
      result = result.replaceAll(RegExp(r'__([^_]+)__'), '\$1');
      result = result.replaceAll(RegExp(r'~~([^~]+)~~'), '\$1');
      
      // Convert markdown bullet lists (- or * at line start) to nice format with •
      // Example: "- Treatment: Use antibiotics" becomes "• Treatment: Use antibiotics"
      final lines = result.split('\n');
      final formatted = <String>[];
      
      for (var line in lines) {
        final trimmed = line.trim();
        
        if (trimmed.isEmpty) {
          // Preserve empty lines for spacing
          if (formatted.isNotEmpty && formatted.last.isNotEmpty) {
            formatted.add('');
          }
        }
        // Markdown headers: ### text → ### text (keep as-is for UI rendering)
        else if (RegExp(r'^#+\s').hasMatch(trimmed)) {
          formatted.add(trimmed);
        }
        // Detect bullet points and convert to •
        else if (trimmed.startsWith('- ')) {
          formatted.add('• ${trimmed.substring(2).trim()}');
        } else if (trimmed.startsWith('* ') && !line.contains('**')) {
          formatted.add('• ${trimmed.substring(2).trim()}');
        } else if (trimmed.startsWith('• ')) {
          formatted.add('• ${trimmed.substring(2).trim()}');
        } 
        // Detect numbered lists: "1. ", "2. ", etc.
        else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
          formatted.add(trimmed);  // Keep numbered lists as-is
        }
        // Regular text
        else {
          formatted.add(trimmed);
        }
      }
      
      result = formatted.join('\n').trim();
      
      // Clean up extra consecutive blank lines (max 2 newlines)
      while (result.contains('\n\n\n')) {
        result = result.replaceAll('\n\n\n', '\n\n');
      }
      
      // Remove any remaining stray asterisks (not part of words)
      result = result.replaceAll(RegExp(r'(?<!\w)\*(?!\w)'), '');
      
      return result;
    } catch (e) {
      print('[RagService] Format error: $e');
      return answer;  // Return original if formatting fails
    }
  }
}
