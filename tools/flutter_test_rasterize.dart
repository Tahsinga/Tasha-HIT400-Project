import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:tasha/services/ocr_worker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final projectRoot = Directory.current.path;
    final candidate = Directory(p.join(projectRoot, 'assets', 'BooksSource'));
    if (!await candidate.exists()) {
      print('Project assets/BooksSource not found at ${candidate.path}');
      exit(1);
    }
    final files = candidate
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();
    if (files.isEmpty) {
      print('No PDFs found in ${candidate.path}');
      exit(1);
    }
    final pdf = files.first;
    print('Using PDF: ${pdf.path}');
    final pages = [1];
    final images = await OcrWorker.rasterizePdfPages(pdf.path, pages, targetWidth: 1400, timeout: Duration(seconds: 60));
    if (images.isEmpty) {
      print('Rasterizer returned no images');
      exit(2);
    }
    final png = images[1];
    if (png == null) {
      print('No image bytes returned for page 1');
      exit(4);
    }
    final out = File(p.join(projectRoot, 'raster_page1.png'));
    await out.writeAsBytes(png);
    print('Wrote raster_page1.png (${await out.length()} bytes)');
    exit(0);
  } catch (e, st) {
    print('Error: $e\n$st');
    exit(3);
  }
}
