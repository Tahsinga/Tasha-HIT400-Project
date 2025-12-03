import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pdf_render/pdf_render.dart';
import '../lib/services/ocr_worker.dart';

// Simple runner: pick the first declared PDF in assets/BooksSource (from pubspec)
// and attempt to rasterize page 1 and write it to a file in the current dir.

Future<void> main() async {
  try {
    // Locate project assets folder
    final projectRoot = Directory.current.path;
    final candidate = Directory(p.join(projectRoot, 'assets', 'BooksSource'));
    if (!await candidate.exists()) {
      print('Project assets/BooksSource not found at ${candidate.path}');
      return;
    }
    final files = candidate
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();
    if (files.isEmpty) {
      print('No PDFs found in ${candidate.path}');
      return;
    }
    final pdf = files.first;
    print('Using PDF: ${pdf.path}');
    final pages = [1];
    final images = await OcrWorker.rasterizePdfPages(pdf.path, pages, targetWidth: 1400, timeout: Duration(seconds: 30));
    if (images.isEmpty) {
      print('Rasterizer returned no images');
      return;
    }
    final png = images[1];
    if (png == null) {
      print('No image bytes returned for page 1');
      return;
    }
    final out = File('raster_page1.png');
    await out.writeAsBytes(png);
    print('Wrote raster_page1.png (${await out.length()} bytes)');
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}
