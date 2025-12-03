import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tasha/main.dart' as app;
import 'package:tasha/services/vector_db.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Quick index test: TXT asset to DB', (WidgetTester tester) async {
    // Skip app UI entirely - just test VectorDB indexing
    
    // Load a text fallback for the book from bundled assets
    const assetPath = 'assets/txt_books/edliz 2020.txt';
    final txt = await rootBundle.loadString(assetPath);

    expect(txt.isNotEmpty, true, reason: 'Text fallback asset should be present for test');

    // Index the text directly using VectorDB.indexTextForBook (no embeddings)
    final bookId = 'edliz 2020.pdf';
    final inserted = await VectorDB.indexTextForBook(bookId, txt, embedder: null, chunkSize: 1000);
    expect(inserted > 0, true, reason: 'indexTextForBook should have inserted chunks');

    // Verify chunks count via VectorDB.chunksCountForBook
    final count = await VectorDB.chunksCountForBook(bookId);
    expect(count >= inserted, true, reason: 'chunksCountForBook should reflect inserted chunks');
    
    print('[TEST] SUCCESS: Indexed $inserted chunks, verified count=$count');
  }, timeout: Timeout(Duration(minutes: 5)));
}
