import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pdf_render/pdf_render.dart';

/// Simple OCR worker that rasterizes PDF pages in a background isolate.
/// The actual OCR (ML Kit) should run on the main isolate.
class OcrWorker {
  /// Rasterize the requested [pages] from [pdfPath] to image bytes.
  /// Returns a map where keys are 1-based page numbers and values are image bytes.
  static Future<Map<int, Uint8List>> rasterizePdfPages(
    String pdfPath,
    List<int> pages, {
    int targetWidth = 1000,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final p = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    try {
      await Isolate.spawn<_IsolateRequest>(
        _isolateEntrypoint,
        _IsolateRequest(pdfPath, pages, targetWidth, p.sendPort),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );

      final completer = Completer<Map<int, Uint8List>>();

      StreamSubscription? sub;
      sub = p.listen((message) {
        try {
          if (message is Map) {
            final out = <int, Uint8List>{};
            message.forEach((k, v) {
              if (k is int && v is List<int>) {
                out[k] = Uint8List.fromList(v);
              } else if (k is String) {
                final ki = int.tryParse(k) ?? -1;
                if (ki > 0 && v is List<int>) {
                  out[ki] = Uint8List.fromList(v);
                }
              }
            });
            if (!completer.isCompleted) completer.complete(out);
          } else if (message == 'done') {
            if (!completer.isCompleted) completer.complete(<int, Uint8List>{});
          }
        } catch (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        }
      });

      final errSub = errorPort.listen((err) {
        if (!completer.isCompleted) completer.completeError(err);
      });

      final result = await completer.future.timeout(timeout, onTimeout: () {
        throw TimeoutException('Rasterization timed out');
      });

      await sub.cancel();
      await errSub.cancel();
      return result;
    } finally {
      p.close();
      errorPort.close();
      exitPort.close();
    }
  }
}

class _IsolateRequest {
  final String pdfPath;
  final List<int> pages;
  final int targetWidth;
  final SendPort replyTo;

  _IsolateRequest(this.pdfPath, this.pages, this.targetWidth, this.replyTo);
}

Future<void> _isolateEntrypoint(_IsolateRequest req) async {
  final Map<int, List<int>> out = {};
  try {
    final doc = await PdfDocument.openFile(req.pdfPath);
    for (final pnum in req.pages) {
      try {
        if (pnum < 1) continue;

        final page = await (doc as dynamic).getPage(pnum);
        if (page == null) continue;

        dynamic pageImage;
        try {
          pageImage = await (page as dynamic).render(width: req.targetWidth);
        } catch (_) {
          try {
            pageImage = await (page as dynamic).render(width: (req.targetWidth * 3) ~/ 4);
          } catch (_) {
            pageImage = null;
          }
        }

        List<int>? bytesList;
        if (pageImage != null) {
          bytesList = await _extractImageBytes(pageImage);
        }

        if (bytesList != null && bytesList.isNotEmpty) {
          out[pnum] = bytesList;
        }

        await _closePage(page);
      } catch (_) {
        // Continue on per-page errors
      }
    }

    await _closeDoc(doc);
  } catch (_) {
    // Return empty map on error
  }

  try {
    req.replyTo.send(out);
  } catch (_) {}
  try {
    req.replyTo.send('done');
  } catch (_) {}
}

/// Extract bytes from a rendered image.
Future<List<int>?> _extractImageBytes(dynamic pageImage) async {
  try {
    if (pageImage == null) return null;

    final raw = (pageImage as dynamic).bytes ?? (pageImage as dynamic).rawBytes;
    if (raw == null) return null;

    List<int>? result;

    if (raw is Uint8List) {
      // Check if already PNG (magic bytes 0x89 'PNG')
      if (raw.length > 8 &&
          raw[0] == 0x89 &&
          raw[1] == 0x50 &&
          raw[2] == 0x4E &&
          raw[3] == 0x47) {
        result = raw.toList();
      } else {
        // Return raw bytes; ML Kit can handle various formats
        result = raw.toList();
      }
    } else if (raw is List<int>) {
      result = List<int>.from(raw);
    }

    return result;
  } catch (_) {
    return null;
  }
}

/// Close a page.
Future<void> _closePage(dynamic page) async {
  try {
    if (page == null) return;
    if ((page as dynamic).close is Function) {
      await (page as dynamic).close();
    } else if ((page as dynamic).dispose is Function) {
      await (page as dynamic).dispose();
    }
  } catch (_) {}
}

/// Close a PDF document.
Future<void> _closeDoc(dynamic doc) async {
  try {
    if (doc == null) return;
    if ((doc as dynamic).dispose is Function) {
      await (doc as dynamic).dispose();
    } else if ((doc as dynamic).close is Function) {
      await (doc as dynamic).close();
    }
  } catch (_) {}
}
