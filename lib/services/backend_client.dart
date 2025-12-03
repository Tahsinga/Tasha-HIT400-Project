// Backend HTTP client for Tasha bot
// All OpenAI calls go through the secure backend server
// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;

class BackendClient {
  final String backendUrl; // e.g., "http://localhost:8000" or "https://api.myserver.com"
  final String appAuthToken; // Your app-level token (not OpenAI key)
  
  BackendClient({
    required this.backendUrl,
    required this.appAuthToken,
  });

  // Make a POST request with auth
  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> payload) async {
    final url = Uri.parse('$backendUrl$endpoint');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $appAuthToken'
    };
    
    try {
      final String rawPayload = jsonEncode(payload);
      // Truncate payload for logs to avoid overwhelming the console
      final String preview = rawPayload.length > 4000 ? rawPayload.substring(0, 4000) + '...<truncated>' : rawPayload;
      print('[BackendClient] POST $endpoint payload_size=${rawPayload.length} payload_preview=$preview');
      final res = await http.post(url, headers: headers, body: rawPayload)
          .timeout(const Duration(seconds: 45));
      
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        print('[BackendClient] POST $endpoint success');
        return decoded;
      } else if (res.statusCode == 401) {
        print('[BackendClient] Unauthorized (invalid auth token)');
        throw Exception('Unauthorized: Invalid auth token. Status=${res.statusCode}');
      } else if (res.statusCode == 429) {
        print('[BackendClient] Rate limited');
        throw Exception('Rate limited by backend. Try again in 1 minute.');
      } else if (res.statusCode == 504) {
        print('[BackendClient] Timeout from OpenAI');
        throw Exception('Backend timeout. OpenAI took too long. Try with shorter chunks.');
      } else {
        final body = res.body;
        print('[BackendClient] POST $endpoint failed status=${res.statusCode} body=$body');
        throw Exception('Backend error: ${res.statusCode} $body');
      }
    } on http.ClientException catch (e) {
      print('[BackendClient] Network error: $e');
      throw Exception('Network error: ${e.toString()}');
    } catch (e) {
      print('[BackendClient] Error: $e');
      rethrow;
    }
  }

  /// Process a single chunk with OpenAI
  Future<String> processChunk(
    String chunk, {
    String model = 'gpt-4o-mini',
    double temperature = 0.0,
    int maxTokens = 512,
    String? systemPrompt,
  }) async {
    final payload = {
      'chunk': chunk,
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
    };
    
    final res = await _post('/process_chunk', payload);
    if (res['success'] == true) {
      return res['result']?.toString() ?? '';
    }
    throw Exception('Process failed: ${res['error']}');
  }

  /// Get embeddings for multiple texts
  Future<List<List<double>>> getEmbeddings(
    List<String> texts, {
    String model = 'text-embedding-3-small',
  }) async {
    final payload = {
      'texts': texts,
      'model': model,
    };
    
    final res = await _post('/embeddings', payload);
    if (res['success'] == true) {
      final List<dynamic> embList = res['embeddings'] as List<dynamic>;
      return embList
          .map((emb) => (emb as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList())
          .toList();
    }
    throw Exception('Embeddings failed: ${res['error']}');
  }

  /// RAG: Answer a question using chunks
  Future<Map<String, dynamic>> ragAnswer(
    String question,
    List<Map<String, dynamic>> chunks, {
    String model = 'gpt-4o-mini',
    double temperature = 0.0,
    int maxTokens = 600,
    String? systemPrompt,
    String? apiKey,  // Optional: pass OpenAI key from app Settings
  }) async {
    // ✅ LOG CHUNKS BEING SENT TO BACKEND
    print('[BackendClient] 📤 RAG REQUEST - Sending ${chunks.length} chunks to backend for question: "$question"');
    var totalChars = 0;
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final text = (chunk['text'] ?? '').toString();
      totalChars += text.length;
      final preview = text.length > 100 ? text.substring(0, 100) + '...' : text;
      print('  📦 Chunk[$i] book="${chunk['book']}" page=${chunk['start_page']} len=${text.length} preview="$preview"');
    }
    print('[BackendClient] ✅ TOTAL CHARS BEING SENT TO OPENAI: $totalChars bytes');
      print('[BackendClient] DEBUG: ragAnswer apiKey parameter = ${apiKey != null ? "YES (${apiKey.length} chars, first 10: ${apiKey.substring(0, 10)}...)" : "NO/NULL"}');
    
    final payload = {
      'question': question,
      'chunks': chunks,
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
    };
    
    final res = await _post('/rag/answer', payload);
    if (res['success'] == true) {
      print('[BackendClient] ✅ RAG RESPONSE RECEIVED: answer_length=${(res['answer'] ?? '').toString().length}');
      return {
        'answer': res['answer']?.toString() ?? '',
        'citations': res['citations'] as List<dynamic>? ?? [],
        'confidence': (res['confidence'] as num?)?.toDouble() ?? 0.5,
      };
    }
    throw Exception('RAG failed: ${res['error']}');
  }

  /// Train a book by generating Q/A pairs
  Future<List<Map<String, dynamic>>> trainBook(
    String bookId,
    List<Map<String, dynamic>> chunks, {
    String model = 'gpt-4o-mini',
    double temperature = 0.0,
    int maxTokens = 800,
  }) async {
    final payload = {
      'book_id': bookId,
      'chunks': chunks,
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    
    final res = await _post('/train/book', payload);
    if (res['success'] == true) {
      final List<dynamic> pairs = res['qa_pairs'] as List<dynamic>? ?? [];
      return pairs.map((p) => Map<String, dynamic>.from(p as Map)).toList();
    }
    throw Exception('Training failed: ${res['error']}');
  }

  /// Health check
  Future<bool> healthCheck() async {
    try {
      final url = Uri.parse('$backendUrl/health');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
