import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;
import '../services/backend_client.dart';
import '../services/backend_config.dart';
import '../services/embedding_service.dart';
import '../services/rag_service.dart';
import '../services/vector_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatRagPage extends StatefulWidget {
  const ChatRagPage({super.key});

  @override
  State<ChatRagPage> createState() => _ChatRagPageState();
}

class _ChatRagPageState extends State<ChatRagPage> {
  final TextEditingController _ctrl = TextEditingController();
  String _answer = '';
  bool _loading = false;

  Future<String?> _getKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('OPENAI_API_KEY');
  }

  Future<void> _onAsk() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    
    // First, ensure the book is indexed (silently in background)
    try {
      // Get active book from main app state if available
      // For now, we'll just index what's available in VectorDB
      final allBooks = await VectorDB.allChunks();
      print('[ChatRag] Available chunks in DB: ${allBooks.length}');
    } catch (e) {
      print('[ChatRag] Pre-indexing check failed (non-critical): $e');
    }
    
    final key = await _getKey();
      print('[ChatRag] DEBUG: _getKey() returned: ${key != null ? "YES (${key.length} chars, first 10: ${key.substring(0, 10)}...)" : "NO/NULL"}');
    // quick connectivity check (try early so we don't attempt embeddings when offline)
    bool online = true;
    try {
      final res = await InternetAddress.lookup('example.com').timeout(
          const Duration(seconds: 3));
      online = res.isNotEmpty && res[0].rawAddress.isNotEmpty;
    } catch (_) {
      online = false;
    }

    // If no API key or offline, use offline answer path and avoid calling embeddings or chat API
    if (key == null || key.isEmpty || !online) {
      try {
        // For offline mode, create a dummy backend client since we only use local VectorDB
        final backend = await BackendConfig.getInstance();
        final emb = EmbeddingService(backend);
        // If embeddings/index exist, try to use them; otherwise fallback to allChunks
        List<Map<String, dynamic>> chunks = [];
        try {
          // try scoped retrieval if precomputed embeddings available
          chunks = await VectorDB.allChunks();
        } catch (_) {
          chunks = await VectorDB.allChunks();
        }
        final rag = RagService(emb, backend);
        final ans = await rag.answerOffline(q, chunks);
        final formatted = rag.formatAnswerForDisplay(ans);
        if (mounted) setState(() {
          _answer = formatted;
          _loading = false;
        });
        return;
      } catch (e) {
        if (mounted) setState(() {
          _answer = 'Offline error: ${e.toString()}';
          _loading = false;
        });
        return;
      }
    }

    // Online + have API key: proceed with proper retrieval + chat
    try {
      final backend = await BackendConfig.getInstance();
      final emb = EmbeddingService(backend);
      final rag = RagService(emb, backend);
      // If DB has no chunks yet, attempt a silent TXT fallback indexing pass so chat can use content
      try {
        final existing = await VectorDB.allChunks();
        if (existing.isEmpty) {
          print('[ChatRag] No chunks found — indexing TXT fallbacks silently before retrieval');
          await _indexAllTxtFallbacks();
        }
      } catch (e) {
        print('[ChatRag] Pre-indexing fallback failed: $e');
      }

      final chunks = await rag.retrieve(q, topK: 12);
      final res = await rag.answerWithOpenAI(q, chunks, apiKey: key);
      final a = (res['answer'] ?? '')?.toString() ?? '';
      final formatted = rag.formatAnswerForDisplay(a);
      if (mounted) setState(() {
        _answer = formatted;
        _loading = false;
      });
    } catch (e) {
      // If anything fails, fall back to offline answer using whatever chunks we have
      try {
        final backend = await BackendConfig.getInstance();
        final fallbackChunks = await VectorDB.allChunks();
        final rag = RagService(EmbeddingService(backend), backend);
        final ans = await rag.answerOffline(q, fallbackChunks);
        final formatted = rag.formatAnswerForDisplay(ans);
        if (mounted) setState(() {
          _answer = formatted;
          _loading = false;
        });
      } catch (e2) {
        if (mounted) setState(() {
          _answer = 'Error: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  // Index all TXT fallback files found in application Documents/TxtBooks silently (no embeddings)
  Future<void> _indexAllTxtFallbacks() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final txtDir = Directory('${docDir.path}${Platform.pathSeparator}TxtBooks');
      if (!await txtDir.exists()) return;
      final files = txtDir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.txt')).toList();
      for (var f in files) {
        try {
          final base = f.path.split(Platform.pathSeparator).last;
          print('[ChatRag] Indexing fallback TXT ${base}');
          final txt = await f.readAsString();
          if (txt.trim().isNotEmpty) {
            await VectorDB.indexTextForBook(base, txt, embedder: null, chunkSize: 1000);
          }
        } catch (e) {
          print('[ChatRag] Failed indexing ${f.path}: $e');
        }
      }
    } catch (e) {
      print('[ChatRag] _indexAllTxtFallbacks error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat (RAG)')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: _buildAnswerDisplay(),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Ask a question...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 8),
                _loading
                    ? const CircularProgressIndicator()
                    : IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _onAsk,
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  /// Build a nicely formatted answer display with bullet points and proper spacing
  Widget _buildAnswerDisplay() {
    if (_answer.isEmpty) {
      return const Center(
        child: Text(
          'Ask a question about the book...',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Split answer by lines and build rich text with proper formatting
    final lines = _answer.split('\n');
    final widgets = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        // Add spacing for empty lines
        if (widgets.isNotEmpty && widgets.last is! SizedBox) {
          widgets.add(const SizedBox(height: 12));
        }
        continue;
      }

      // Section headers: ### text or ## text or # text
      if (RegExp(r'^#+\s').hasMatch(trimmed)) {
        final headerText = trimmed.replaceAll(RegExp(r'^#+\s'), '').trim();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
            child: Text(
              headerText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        );
      }
      // Bullet point formatting: • text or - text or * text
      else if (trimmed.startsWith('•') || 
               (trimmed.startsWith('- ') && !trimmed.contains('**')) ||
               (trimmed.startsWith('* ') && !trimmed.contains('**'))) {
        String bulletText = trimmed;
        if (trimmed.startsWith('- ')) {
          bulletText = trimmed.substring(2).trim();
        } else if (trimmed.startsWith('* ')) {
          bulletText = trimmed.substring(2).trim();
        } else if (trimmed.startsWith('•')) {
          bulletText = trimmed.substring(1).trim();
        }

        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8, top: 2),
                  child: Text(
                    '•',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    bulletText,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Numbered list formatting: 1. text, 2. text, etc.
      else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Text(
              trimmed,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        );
      }
      // Regular text or paragraphs
      else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            child: Text(
              trimmed,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets.isEmpty ? [const Text('No response')] : widgets,
    );
  }
}
