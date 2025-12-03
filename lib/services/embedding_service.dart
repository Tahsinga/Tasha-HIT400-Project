// ignore_for_file: avoid_print

import 'backend_client.dart';

class EmbeddingService {
  final BackendClient backend;
  
  EmbeddingService(this.backend);

  /// Embed a single text via backend
  Future<List<double>> embedText(String text) async {
    try {
      print('[EmbeddingService] embedText len=${text.length}');
      final embeddings = await backend.getEmbeddings([text]);
      if (embeddings.isEmpty) {
        throw Exception('No embeddings returned');
      }
      return embeddings.first;
    } catch (e) {
      print('[EmbeddingService] ERROR: $e');
      rethrow;
    }
  }

  /// Embed multiple texts at once (more efficient)
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    try {
      print('[EmbeddingService] embedBatch count=${texts.length}');
      final embeddings = await backend.getEmbeddings(texts);
      return embeddings;
    } catch (e) {
      print('[EmbeddingService] ERROR: $e');
      rethrow;
    }
  }
}
