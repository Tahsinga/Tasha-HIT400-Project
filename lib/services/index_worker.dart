import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

// Entry point for the background indexing isolate.
// Receives a Map with keys: 'main' (SendPort), 'pages' (List<String>), 'bookId', 'maxLen', 'batchSize'
// NOTE: Embeddings are now handled by the backend, not the isolate
Future<void> indexWorker(Map<String, dynamic> msg) async {
  final SendPort mainPort = msg['main'] as SendPort;
  final List<dynamic> pagesDyn = msg['pages'] as List<dynamic>? ?? [];
  final List<String> pages = pagesDyn.map((e) => e?.toString() ?? '').toList();
  final String bookId = msg['bookId']?.toString() ?? '';
  final int maxLen = msg['maxLen'] is int ? msg['maxLen'] as int : 1000;
  final int batchSize = msg['batchSize'] is int ? msg['batchSize'] as int : 4;

  final control = ReceivePort();
  // Send a control port back so the spawner can send cancellation messages.
  mainPort.send({'type': 'control_port', 'port': control.sendPort});

  var cancelled = false;
  control.listen((m) {
    try {
      if (m == null) return;
      if (m is Map && m['cmd'] == 'cancel') {
        cancelled = true;
      }
      if (m is String && m == 'cancel') {
        cancelled = true;
      }
    } catch (_) {}
  });

  // Build chunk metadata list (page index = start_page = end_page for now)
  final chunks = <Map<String, dynamic>>[];
  for (var i = 0; i < pages.length; i++) {
    final text = pages[i];
    if (text.trim().isEmpty) {
      print('[IndexWorker] Page ${i + 1} is empty, skipping');
      continue;
    }
    print('[IndexWorker] Page ${i + 1} has ${text.length} chars');
    for (var start = 0; start < text.length; start += maxLen) {
      final end = (start + maxLen < text.length) ? start + maxLen : text.length;
      final chunkText = text.substring(start, end);
      chunks.add({'start_page': i + 1, 'end_page': i + 1, 'text': chunkText});
    }
  }

  final total = chunks.length;

  // Notify main that worker started and how many chunks will be processed
  try {
    mainPort.send({'type': 'started', 'total': total, 'book': bookId});
  } catch (_) {}

  var done = 0;
  final batch = <Map<String, dynamic>>[];

  try {
    for (var ch in chunks) {
      if (cancelled) break;
      final txt = ch['text']?.toString() ?? '';
      // No embedding here - the main thread or backend will handle that
      batch.add({'start_page': ch['start_page'], 'end_page': ch['end_page'], 'text': txt, 'embedding': null});
      done += 1;

      // send batch when full
      if (batch.length >= batchSize) {
        mainPort.send({'type': 'batch', 'batch': batch, 'done': done, 'total': total, 'book': bookId});
        batch.clear();
        // heartbeat after sending a batch
        try {
          mainPort.send({'type': 'heartbeat', 'done': done, 'total': total, 'book': bookId});
        } catch (_) {}
      }
      // Small cooperative delay to avoid hammering rate limits and give cancellation a chance
      try {
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (_) {}
    }

    if (batch.isNotEmpty && !cancelled) {
      mainPort.send({'type': 'batch', 'batch': batch, 'done': done, 'total': total, 'book': bookId});
      batch.clear();
      try {
        mainPort.send({'type': 'heartbeat', 'done': done, 'total': total, 'book': bookId});
      } catch (_) {}
    }
  } catch (e, st) {
    // Send an error payload back to main so it can log and act accordingly
    try {
  mainPort.send({'type': 'error', 'error': e.toString(), 'stack': st.toString(), 'book': bookId});
    } catch (_) {}
  } finally {
    // Always send final done message so main can finalize
    try {
  mainPort.send({'type': 'done', 'done': done, 'total': total, 'cancelled': cancelled, 'book': bookId});
    } catch (_) {}
    // close control port
    try {
      control.close();
    } catch (_) {}
  }
}
